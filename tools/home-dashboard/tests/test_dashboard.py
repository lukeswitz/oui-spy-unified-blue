# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""Commands, access control and the TAK / Reticulum links: python -m unittest discover -s tests"""
import os
import socket
import sys
import tempfile
import threading
import time
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import access  # noqa: E402
import board_decode as bd  # noqa: E402
import connectors  # noqa: E402
from board_commands import BoardCommander, PlanError  # noqa: E402
from fleet import Fleet  # noqa: E402
from sources import DEMO_HOME, DemoSource  # noqa: E402
from store import Store  # noqa: E402


def wait(cond, secs=5.0):
    end = time.time() + secs
    while time.time() < end:
        if cond():
            return True
        time.sleep(0.02)
    return False


class CommandsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(os.path.join(self.tmp.name, "t.db"))
        self.events = []
        self.fleet = Fleet(self.store, lambda e, p: self.events.append((e, p)))
        self.demo = DemoSource(self.fleet, lambda: None)
        self.demo.set_state(connected=True)
        self.fleet.set_connected_board(DEMO_HOME, True)
        self.cmd = BoardCommander(self.fleet, self.store, lambda e, p: self.events.append((e, p)), lambda: self.demo)
        self.cmd.start()

    def tearDown(self):
        self.tmp.cleanup()

    def test_unsupported_operations_are_refused_plainly(self):
        for op in ("preset", "filters_set", "audio", "rechan", "setkey", "fw_send", "alias"):
            with self.assertRaises(PlanError, msg=op) as cm:
                self.cmd.submit(op, "DE0B", {})
            self.assertIn("OUI-APEX app", str(cm.exception))
        with self.assertRaises(PlanError):
            self.cmd.submit("dance", "DE0B", {})
        with self.assertRaises(PlanError):
            self.cmd.submit("status", "NOT-A-NODE", {})

    def test_status_job_finishes_when_the_node_answers(self):
        self.fleet.apply_config({"node": "DE0B", "role": "remote"})
        job = self.cmd.submit("status", "DE0B")
        self.assertTrue(wait(lambda: self.demo.sent))
        self.assertEqual(self.demo.sent[-1], bd.encode_status_request("DE0B"))
        self.fleet.apply_config({"node": "DE0B", "role": "remote", "fw": "0.7.0"})
        self.assertTrue(wait(lambda: job["state"] == "done"))
        self.assertEqual(job["replies"]["DE0B"]["text"], "status received")

    def test_status_with_no_answer_fails(self):
        import board_commands
        board_commands.STATUS_WINDOW = 0.5
        job = self.cmd.submit("status", "DE0C")
        self.assertTrue(wait(lambda: job["state"] == "failed"))
        self.assertEqual(job["error"], "no status came back")

    def test_identify_and_reboot_say_the_node_does_not_confirm(self):
        j1 = self.cmd.submit("identify", "DE0B", {"secs": 5})
        self.assertTrue(wait(lambda: j1["state"] == "done"))
        self.assertEqual(self.demo.sent[-1], bd.encode_identify("DE0B", 5))
        self.assertIn("does not confirm", j1["replies"]["DE0B"]["text"])
        j2 = self.cmd.submit("reboot", DEMO_HOME)
        self.assertTrue(wait(lambda: j2["state"] == "done"))
        self.assertEqual(self.demo.sent[-1], bd.encode_reboot(None))

    def test_job_fails_without_a_board(self):
        c = BoardCommander(self.fleet, self.store, lambda e, p: None, lambda: None)
        c.start()
        job = c.submit("identify", "DE0B")
        self.assertTrue(wait(lambda: job["state"] == "failed"))
        self.assertEqual(job["error"], "no board on USB")

    def test_jobs_are_saved_and_listed(self):
        job = self.cmd.submit("identify", "DE0B")
        self.assertTrue(wait(lambda: job["state"] == "done"))
        self.assertIn(job["id"], [j["id"] for j in self.cmd.recent("DE0B")])
        self.assertIn(job["id"], [j["id"] for j in self.store.recent_commands("DE0B")])


class AccessTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.tokens = access.TokenStore(os.path.join(self.tmp.name, "cfg", "tok"))

    def tearDown(self):
        self.tmp.cleanup()

    def test_token_is_shown_once_and_only_its_hash_is_kept(self):
        self.assertFalse(self.tokens.exists())
        t = self.tokens.create()
        on_disk = open(self.tokens.path).read()
        self.assertNotIn(t, on_disk)
        self.assertEqual(on_disk.strip(), access.hash_token(t))
        self.assertEqual(os.stat(self.tokens.path).st_mode & 0o777, 0o600)
        self.assertTrue(self.tokens.verify(t))
        self.assertFalse(self.tokens.verify(t + "x"))
        self.assertFalse(self.tokens.verify(""))
        self.assertNotEqual(self.tokens.create(), t)
        self.assertFalse(self.tokens.verify(t))

    def test_only_this_computer_skips_the_token(self):
        t = self.tokens.create()
        self.assertTrue(access.authorized("127.0.0.1", "", None, self.tokens))
        self.assertTrue(access.authorized("::1", "", None, self.tokens))
        self.assertFalse(access.authorized("192.0.2.9", "", None, self.tokens))
        self.assertFalse(access.authorized("192.0.2.9", "", "wrong", self.tokens))
        self.assertTrue(access.authorized("192.0.2.9", "", t, self.tokens))
        self.assertFalse(access.authorized("127.0.0.1", "192.0.2.9", None, self.tokens))
        self.assertTrue(access.authorized("127.0.0.1", "192.0.2.9", t, self.tokens))

    def test_no_token_set_means_no_remote_access(self):
        self.assertFalse(access.authorized("192.0.2.9", "", "anything", self.tokens))

    def test_loopback_only_accepts_loopback_host_names(self):
        self.assertTrue(access.host_allowed("127.0.0.1:5077", 5077, False))
        self.assertTrue(access.host_allowed("localhost:5077", 5077, False))
        self.assertFalse(access.host_allowed("evil.example:5077", 5077, False))
        self.assertFalse(access.host_allowed("127.0.0.1:9999", 5077, False))
        self.assertTrue(access.host_allowed("evil.example:5077", 5077, True))

    def test_cross_site_writes_are_refused(self):
        self.assertTrue(access.origin_allowed("POST", None, "127.0.0.1:5077"))
        self.assertTrue(access.origin_allowed("POST", "http://127.0.0.1:5077", "127.0.0.1:5077"))
        self.assertFalse(access.origin_allowed("POST", "https://evil.example", "127.0.0.1:5077"))
        self.assertTrue(access.origin_allowed("GET", "https://evil.example", "127.0.0.1:5077"))


class LinkSummaryTest(unittest.TestCase):
    def test_summary_has_what_the_app_reads(self):
        snap = {"home": {"id": "A1B2", "alive": True}, "nodes": [{"online": True}, {"online": False}]}
        out = connectors.link_summary(snap, {"serial": {"connected": True, "detail": "x"}},
                                      {"mqtt": {"enabled": False}, "retention_days": 7, "secret": 1}, "live")
        self.assertEqual(out["home"], {"id": "A1B2", "alive": True})
        self.assertEqual(out["nodes"], {"total": 2, "online": 1})
        self.assertEqual(out["board"], {"connected": True, "detail": "x"})
        self.assertEqual(out["settings"]["retention_days"], 7)
        self.assertNotIn("secret", out["settings"])


class TakTest(unittest.TestCase):
    def test_cot_is_valid_xml_with_escaped_text(self):
        x = connectors.cot_event("ouispy-node-A1B2", "a-f-G-U-C", 10.0, 20.0, 'AP "<1>"', "a & b", now=0)
        e = ET.fromstring(x.split("?>", 1)[1])
        self.assertEqual((e.get("uid"), e.get("type")), ("ouispy-node-A1B2", "a-f-G-U-C"))
        self.assertEqual(e.find("point").get("lat"), "10.0000000")
        self.assertEqual(e.find("detail/contact").get("callsign"), 'AP "<1>"')
        self.assertEqual(e.find("detail/remarks").text, "a & b")
        self.assertEqual(e.get("stale"), "1970-01-01T00:01:00Z")

    def test_events_for_nodes_drones_and_pilots(self):
        nodes = [{"id": "A1B2", "alias": "Base", "online": True, "lat": 10.0, "lon": 20.0, "role": "home"},
                 {"id": "C3D4", "online": True, "lat": None, "lon": None},
                 {"id": "E5F6", "online": False, "lat": 1.0, "lon": 2.0}]
        drones = [{"mac": "AA:BB:CC:00:00:01", "id": "UAS-1", "live": True, "lat": 10.1, "lon": 20.1,
                   "plat": 10.2, "plon": 20.2, "rssi": -70},
                  {"mac": "AA:BB:CC:00:00:02", "live": False, "lat": 1.0, "lon": 1.0}]
        ev = [ET.fromstring(x.split("?>", 1)[1]) for x in connectors.events_for(nodes, drones, "OUISPY", now=0)]
        self.assertEqual([e.get("uid") for e in ev],
                         ["ouispy-node-A1B2", "ouispy-drone-AABBCC000001", "ouispy-pilot-AABBCC000001"])
        self.assertEqual(ev[2].find("detail/link").get("uid"), "ouispy-drone-AABBCC000001")

    def test_tcp_push_reaches_a_server_and_status_counts_it(self):
        srv = socket.socket()
        srv.bind(("127.0.0.1", 0))
        srv.listen(1)
        got = []

        def serve():
            c, _ = srv.accept()
            c.settimeout(2)
            got.append(c.recv(65536))
            c.close()
        threading.Thread(target=serve, daemon=True).start()
        cfg = {"enabled": True, "host": "127.0.0.1", "port": srv.getsockname()[1], "proto": "tcp"}
        link = connectors.TakLink(lambda: cfg, lambda: ([], []))
        n = link.push([connectors.cot_event("u", "a-u-G", 1.0, 2.0, "c", now=0)])
        self.assertEqual(n, 1)
        self.assertTrue(wait(lambda: got))
        self.assertIn(b'uid="u"', got[0])
        st = link.status()
        self.assertEqual((st["state"], st["sent"], st["error"]), ("connected", 1, ""))
        link.stop()
        srv.close()

    def test_unreachable_server_reports_an_error(self):
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
        s.close()
        link = connectors.TakLink(lambda: {"enabled": True, "host": "127.0.0.1", "port": port, "proto": "tcp"},
                                  lambda: ([], []))
        self.assertEqual(link.push(["<event/>"]), 0)
        self.assertEqual(link.status()["state"], "error")
        self.assertTrue(link.status()["error"])
        link.stop()

    def test_off_sends_nothing(self):
        link = connectors.TakLink(lambda: {"enabled": False}, lambda: ([], []))
        self.assertEqual(link.push(["<event/>"]), 0)
        self.assertEqual(link.status()["state"], "off")
        link.stop()


class FakeRns:
    class Identity:
        store = {}

        def __init__(self):
            self.n = 1

        @classmethod
        def from_file(cls, p):
            return cls()

        def to_file(self, p):
            open(p, "w").write("x")

        @classmethod
        def recall(cls, h):
            return cls() if h.hex().startswith("aa") else None

    class Destination:
        OUT, SINGLE = 1, 2

        def __init__(self, ident, direction, kind, app, aspect):
            self.parts = (app, aspect)

    class Transport:
        asked = []

        @classmethod
        def request_path(cls, h):
            cls.asked.append(h)

    class Reticulum:
        pass

    @staticmethod
    def hexrep(h, delimit=True):
        return h.hex()


class FakeLxmf:
    sent = []

    class LXMRouter:
        def __init__(self, storagepath=None):
            pass

        def register_delivery_identity(self, ident, display_name=None):
            class D:
                hash = bytes.fromhex("0123456789abcdef0123456789abcdef")
            return D()

        def announce(self, h):
            pass

        def handle_outbound(self, m):
            FakeLxmf.sent.append(m)

    class LXMessage:
        DIRECT = 2

        def __init__(self, dest, src, content, title, desired_method=None):
            self.content = content


class ReticulumTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        FakeLxmf.sent.clear()

    def tearDown(self):
        self.tmp.cleanup()

    def link(self, cfg):
        return connectors.ReticulumLink(lambda: cfg, FakeRns, FakeLxmf,
                                        os.path.join(self.tmp.name, "id", "identity"))

    def test_alert_is_delivered_to_each_recipient_and_counted(self):
        cfg = {"enabled": True, "recipients": ["aa" * 16, "ab" * 16], "send": {"new_devices": True}}
        link = self.link(cfg)
        link.alert("new_devices", "New device X")
        self.assertTrue(wait(lambda: link.status()["sent"] == 1))
        self.assertTrue(wait(lambda: link.status()["failed"] == 1))
        self.assertEqual(FakeLxmf.sent[0].content, "New device X")
        st = link.status()
        self.assertEqual((st["state"], st["address"]), ("connected", "0123456789abcdef0123456789abcdef"))
        self.assertIn("no path", st["error"])
        self.assertEqual(os.stat(os.path.join(self.tmp.name, "id", "identity")).st_mode & 0o777, 0o600)
        link.stop()

    def test_off_and_muted_kinds_queue_nothing(self):
        link = self.link({"enabled": False, "recipients": ["aa" * 16]})
        link.alert("drones", "x")
        self.assertEqual(link.status()["queued"], 0)
        link.stop()
        link = self.link({"enabled": True, "recipients": ["aa" * 16], "send": {"drones": False}})
        link.alert("drones", "x")
        self.assertEqual(link.status()["queued"], 0)
        link.stop()

    def test_alerts_of_one_kind_are_spaced_out(self):
        link = self.link({"enabled": True, "recipients": ["aa" * 16]})
        link.alert("drones", "one")
        link.alert("drones", "two")
        self.assertTrue(wait(lambda: link.status()["sent"] >= 1))
        time.sleep(0.3)
        self.assertEqual([m.content for m in FakeLxmf.sent], ["one"])
        link.stop()


if __name__ == "__main__":
    unittest.main()
