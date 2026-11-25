# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT
# Job shape and queue follow OUI-SPY Detector home-dashboard commands.py, Copyright (c) 2025-2026 colonelpanichacks (MIT)

"""Node commands from the dashboard, sent down the board link.

Supported: read status, identify, reboot, to one node or the whole mesh. The firmware has no
other remote control from a computer (filters, presets, buzzer, channel and updates are set from
the OUI-APEX app), so every other operation is refused with a plain message.

One job runs at a time. Status jobs finish when the node's detail arrives in the mesh status.
Identify and reboot are not confirmed by the node: the job finishes when the board has taken the
command, and says so.
"""
import itertools
import queue
import threading
import time

import board_decode as bd

LABELS = {"status": "Read status", "identify": "Identify", "reboot": "Reboot"}
UNSUPPORTED = {"alias", "audio", "preset", "filters_get", "filters_set", "filters_add", "filters_del",
               "rechan", "meshpush", "setkey", "fw_stage", "fw_send", "fw_self"}
STATUS_WINDOW = 12.0
JOIN_READ_GAP = 30.0


class PlanError(ValueError):
    pass


class BoardCommander:
    def __init__(self, fleet, store, emit, get_sender):
        self.fleet = fleet
        self.store = store
        self.emit = emit
        self.get_sender = get_sender
        self.ids = itertools.count(int(time.time()) % 1000000 * 10)
        self.q = queue.Queue()
        self.jobs = {}
        self.lock = threading.Lock()
        self.joined = {}
        self.thread = None

    def start(self):
        self.thread = threading.Thread(target=self._worker, daemon=True, name="board-commands")
        self.thread.start()

    def plan(self, op, target, args):
        if op in UNSUPPORTED:
            raise PlanError("the OUI-APEX firmware cannot do this from the dashboard; use the OUI-APEX app")
        if op not in LABELS:
            raise PlanError(f"unknown operation {op!r}")
        if target != "all" and not (isinstance(target, str) and len(target) == 4):
            raise PlanError("target must be a node ID or all")
        label = LABELS[op]
        if op == "identify":
            secs = max(1, min(120, int((args or {}).get("secs") or 10)))
            label = f"Identify {secs} s"
            payload_for = lambda t: bd.encode_identify(t, seconds=secs)
        elif op == "reboot":
            payload_for = bd.encode_reboot
        else:
            payload_for = bd.encode_status_request
        return label, payload_for

    def submit(self, op, target, args=None, auto=False):
        label, payload_for = self.plan(op, target, args)
        job = {"id": next(self.ids), "op": op, "target": target, "label": label,
               "expect": "rst" if op == "status" else "sent", "lines": [], "kinds": [],
               "state": "queued", "cmd_id": None, "replies": {}, "error": "",
               "created": time.time(), "finished": None, "auto": auto, "args": args or {}}
        with self.lock:
            self.jobs[job["id"]] = job
            for k in sorted(self.jobs)[:-200]:
                del self.jobs[k]
        self._publish(job)
        self.q.put((job, payload_for))
        return job

    def recent(self, node=None, limit=60):
        with self.lock:
            rows = [dict(j) for j in self.jobs.values() if node is None or j["target"] in (node, "all")]
        rows.sort(key=lambda j: j["created"], reverse=True)
        return rows[:limit]

    def node_joined(self, nid):
        now = time.time()
        if nid == self.fleet.home_id or now - self.joined.get(nid, 0) < JOIN_READ_GAP:
            return
        self.joined[nid] = now
        if self.get_sender() is not None and self.thread is not None:
            self.submit("status", nid, auto=True)

    def _publish(self, job):
        self.store.save_command(job)
        self.emit("job", {k: v for k, v in job.items() if k != "args"})

    def _worker(self):
        while True:
            job, payload_for = self.q.get()
            try:
                self._run(job, payload_for)
            except Exception as e:
                self._finish(job, "failed", f"{type(e).__name__}: {e}")

    def _finish(self, job, state, error=""):
        job["state"], job["error"], job["finished"] = state, error, time.time()
        self._publish(job)

    def _targets(self, job):
        home = self.fleet.home_id
        if job["target"] == "all":
            with self.fleet.lock:
                return [n for n, st in self.fleet.nodes.items() if st["online"] and n != home]
        return [job["target"]]

    def _run(self, job, payload_for):
        sender = self.get_sender()
        if sender is None:
            return self._finish(job, "failed", "no board on USB")
        job["state"] = "waiting"
        self._publish(job)
        home = self.fleet.home_id
        local = job["target"] == home
        started = time.time()
        wire = None if (job["target"] == "all" or local) else job["target"]
        if not sender.control(payload_for(wire)):
            return self._finish(job, "failed", "the board did not take the command")
        who = self._targets(job)
        if job["op"] != "status":
            text = "sent to the mesh; the node does not confirm"
            for n in who or [home]:
                if n:
                    job["replies"][n] = {"st": 0, "text": text, "ts": time.time()}
            return self._finish(job, "done")
        deadline = started + STATUS_WINDOW
        while time.time() < deadline:
            for n in who or [home]:
                if not n or n in job["replies"]:
                    continue
                with self.fleet.lock:
                    ts = (self.fleet.nodes.get(n) or {}).get("cfg_ts") or 0
                if ts >= started:
                    job["replies"][n] = {"st": 0, "text": "status received", "ts": ts}
            if job["replies"] and all(n in job["replies"] for n in (who or [home]) if n):
                return self._finish(job, "done")
            time.sleep(0.25)
        if job["replies"]:
            return self._finish(job, "done")
        self._finish(job, "failed", "no status came back")
