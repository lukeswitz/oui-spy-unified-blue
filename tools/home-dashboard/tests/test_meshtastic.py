# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""The Meshtastic link against a fake radio (no real radio): python -m unittest discover -s tests"""
import importlib
import os
import socket
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import access  # noqa: E402
import meshtastic_link as ml  # noqa: E402
import mt_codec as mt  # noqa: E402
from fakeradio import ME, PEER, FakeRadio  # noqa: E402

try:
    import flask  # noqa: F401
    import flask_socketio  # noqa: F401
    HAVE_FLASK = True
except ImportError:
    HAVE_FLASK = False


def wait(cond, secs=5.0):
    end = time.time() + secs
    while time.time() < end:
        if cond():
            return True
        time.sleep(0.02)
    return False


def cfg(**kw):
    c = ml.defaults()
    c.update({"enabled": True, "port": "/dev/ttyUSB0", "channel": 1}, **kw)
    return c


class CodecTest(unittest.TestCase):
    def test_want_config_and_frame_bytes(self):
        self.assertEqual(mt.to_radio_want_config(1), bytes.fromhex("1801"))
        self.assertEqual(mt.frame(bytes.fromhex("1801")), bytes.fromhex("94c3000218" "01"))
        self.assertEqual(mt.to_radio_heartbeat(), bytes.fromhex("3a00"))

    def test_text_packet_bytes_match_the_field_numbers(self):
        got = mt.to_radio_text("hi", 1, 0x01020304)
        want = bytes.fromhex("0a16" "15ffffffff" "1801" "2206080112026869" "3504030201" "4803")
        self.assertEqual(got, want)
        direct = mt.to_radio_text("hi", 0, 1, to=0x0B0C0D0E)
        self.assertIn(bytes.fromhex("150e0d0c0b"), direct)
        self.assertNotIn(bytes.fromhex("1800"), direct)

    def test_frame_refuses_a_payload_over_512(self):
        mt.frame(b"x" * 512)
        with self.assertRaises(ValueError):
            mt.frame(b"x" * 513)

    def test_deframer_skips_debug_text_and_joins_split_frames(self):
        d = mt.Deframer()
        f1, f2 = mt.frame(b"\x18\x01"), mt.frame(b"\x18\x02")
        data = b"INFO | boot\r\n" + f1 + b"\x94junk" + f2
        out = []
        for i in range(0, len(data), 3):
            out += d.feed(data[i:i + 3])
        self.assertEqual(out, [b"\x18\x01", b"\x18\x02"])

    def test_deframer_drops_a_length_over_512_and_resyncs(self):
        d = mt.Deframer()
        out = d.feed(bytes([0x94, 0xC3, 0x02, 0x01]) + b"\x00" * 6 + mt.frame(b"\x18\x07"))
        self.assertEqual(out, [b"\x18\x07"])

    def test_clip_text_cuts_on_a_character_boundary_and_strips_controls(self):
        t = mt.clip_text("é" * 150)
        self.assertLessEqual(len(t.encode("utf-8")), 200)
        t.encode("utf-8").decode("utf-8")
        self.assertEqual(mt.clip_text("a\x00b\nc\x7f"), "a b c")

    def test_from_radio_messages(self):
        user = mt.f_bytes(2, b"Long") + mt.f_bytes(3, b"Sh")
        node = mt.parse_from_radio(mt.f_varint(1, 5) + mt.f_bytes(4, mt.f_varint(1, 9) + mt.f_bytes(2, user)))
        self.assertEqual(node, {"kind": "node_info", "node": 9, "long": "Long", "short": "Sh"})
        ch = mt.parse_from_radio(mt.f_bytes(10, mt.f_varint(1, 1) + mt.f_bytes(2, mt.f_bytes(2, b"k" * 32)
                                                                           + mt.f_bytes(3, b"Fleet")) + mt.f_varint(3, 2)))
        self.assertEqual(ch, {"kind": "channel", "index": 1, "role": 2, "name": "Fleet", "psk_len": 32})
        self.assertEqual(mt.parse_from_radio(mt.f_bytes(3, mt.f_varint(1, 77))), {"kind": "my_info", "node": 77})
        self.assertEqual(mt.parse_from_radio(mt.f_varint(7, 123)), {"kind": "config_complete", "id": 123})
        self.assertEqual(mt.parse_from_radio(mt.f_varint(8, 1)), {"kind": "rebooted"})
        self.assertEqual(mt.parse_from_radio(b"\xff"), {"kind": "other"})
        self.assertEqual(mt.parse_from_radio(b"\x0a\x7f\x01"), {"kind": "other"})

    def test_node_ids(self):
        self.assertEqual(mt.node_id(0x0A1B2C3D), "!0a1b2c3d")
        self.assertEqual(mt.parse_node_id("!0A1B2C3D"), 0x0A1B2C3D)
        for bad in ("0a1b2c3d", "!0a1b2c3", "!0a1b2c3dd", "!0a1b2c3g", ""):
            self.assertIsNone(mt.parse_node_id(bad), bad)


class SettingsTest(unittest.TestCase):
    def test_everything_is_off_by_default(self):
        d = ml.defaults()
        self.assertFalse(d["enabled"])
        self.assertEqual(d["port"], "")
        self.assertEqual(d["send"], {"new_devices": False, "drones": False, "lost_nodes": False, "nodes": False})
        self.assertEqual(ml.merged(None), d)
        self.assertEqual(ml.merged({"enabled": "yes", "channel": "x", "send": {"drones": 1}}), d)

    def test_a_port_is_a_serial_device_or_a_tcp_target_and_nothing_else(self):
        for good in ("/dev/ttyUSB0", "/dev/cu.usbmodem1101", "COM5", "tcp:192.0.2.7", "tcp:radio.local:4403", ""):
            self.assertEqual(ml.clean_port(good), good)
        for bad in ("/etc/passwd", "/dev/ttyUSB0/../../etc/passwd", "/dev/tty", "/dev/sda", "tcp:", "tcp:host:0",
                    "tcp:host:70000", "file:///etc/hosts", "http://192.0.2.7", "/dev/ttyUSB0 x", "../dev/ttyUSB0", "COM"):
            with self.assertRaises(ValueError, msg=bad):
                ml.clean_port(bad)

    def test_update_keeps_known_keys_and_checks_them(self):
        out = ml.clean_meshtastic({"enabled": True, "port": "tcp:192.0.2.7", "channel": "2", "evil": 1,
                                   "recipients": "!0b0c0d0e, !0B0C0D0F", "send": {"drones": True, "bogus": True}}, {})
        self.assertEqual(out, {"enabled": True, "port": "tcp:192.0.2.7", "channel": 2,
                               "recipients": ["!0b0c0d0e", "!0b0c0d0f"],
                               "send": {"new_devices": False, "drones": True, "lost_nodes": False, "nodes": False}})
        for bad in ({"channel": 8}, {"channel": -1}, {"channel": "x"}, {"recipients": ["nope"]},
                    {"recipients": [f"!0b0c0d0{i}" for i in range(5)]}, {"enabled": True}):
            with self.assertRaises(ValueError, msg=str(bad)):
                ml.clean_meshtastic(bad, {})

    def test_the_boards_serial_port_cannot_be_the_radio_port(self):
        with self.assertRaises(ValueError):
            ml.clean_meshtastic({"port": "/dev/ttyACM0"}, {}, board_port="/dev/ttyACM0")
        ml.clean_meshtastic({"port": "/dev/ttyUSB0"}, {}, board_port="/dev/ttyACM0")


class OutboxTest(unittest.TestCase):
    def test_batches_one_message_per_kind_per_gap(self):
        ob = ml.Outbox(kind_gap=60)
        for t in ("Flock BLE at North", "Flock BLE at North", "Detector at Ridge"):
            ob.add("new_devices", t, 0)
        self.assertEqual(ob.next(0), ("new_devices", "OUI-APEX new devices: Flock BLE at North x2; Detector at Ridge"))
        ob.add("new_devices", "Camera at Gate", 10)
        self.assertIsNone(ob.next(10))
        self.assertIsNone(ob.next(59.9))
        self.assertEqual(ob.next(60)[1], "OUI-APEX new devices: Camera at Gate")
        self.assertEqual(ob.pending(), 0)

    def test_kinds_have_their_own_gap(self):
        ob = ml.Outbox(kind_gap=60)
        ob.add("new_devices", "a", 0)
        ob.add("drones", "UAS-1", 0)
        self.assertEqual(ob.next(0)[0], "new_devices")
        self.assertEqual(ob.next(0)[0], "drones")

    def test_a_long_batch_is_cut_to_200_bytes_with_a_count(self):
        ob = ml.Outbox()
        for i in range(40):
            ob.add("new_devices", f"Vendor name number {i} at Ridge Relay", 0)
        kind, text = ob.next(0)
        self.assertLessEqual(len(text.encode("utf-8")), 200)
        self.assertRegex(text, r"\(\+\d+ more\)$")
        self.assertTrue(text.startswith("OUI-APEX new devices: Vendor name number 0 at Ridge Relay"))

    def test_old_items_expire_and_the_queue_is_capped(self):
        ob = ml.Outbox(ttl=100, cap=3)
        ob.add("drones", "old", 0)
        self.assertIsNone(ob.next(101))
        for i in range(5):
            ob.add("drones", f"d{i}", 200)
        self.assertEqual(ob.next(200)[1], "OUI-APEX drones: d2; d3; d4 (+2 more)")

    def test_a_test_goes_first_and_only_one_waits(self):
        ob = ml.Outbox()
        ob.add("drones", "x", 0)
        self.assertTrue(ob.queue_test())
        self.assertFalse(ob.queue_test())
        self.assertEqual(ob.next(0), ("test", ml.TEST_TEXT))
        self.assertEqual(ob.next(0)[0], "drones")


class LinkTest(unittest.TestCase):
    def setUp(self):
        self.radios, self.links = [], []

    def tearDown(self):
        for link in self.links:
            link.stop()
        for r in self.radios:
            r.hang_up()

    def radio(self, **kw):
        r = FakeRadio(**kw)
        self.radios.append(r)
        return r

    def link(self, config, radio=None, **kw):
        radio = radio or self.radio()
        self.config = config
        args = dict(kind_gap=0.4, global_gap=0.05, retry=(0.05, 0.1), cfg_ttl=0, handshake_wait=1.0)
        args.update(kw)
        link = ml.MeshtasticLink(lambda: self.config, opener=lambda port: radio.transport(), **args)
        self.links.append(link)
        return link, radio

    def test_handshake_reads_the_radio_and_the_channel_list(self):
        link, radio = self.link(cfg())
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        st = link.status()
        self.assertEqual((st["radio"], st["radio_name"], st["channel_name"]), ("!0a1b2c3d", "Dashboard Radio", "Fleet"))
        self.assertEqual(st["channels"], [{"index": 0, "name": "LongFast", "role": "primary", "private": False},
                                          {"index": 1, "name": "Fleet", "role": "secondary", "private": True}])
        self.assertEqual(radio.rx[0]["kind"], "want_config")
        self.assertEqual(radio.handshakes, 1)

    def test_off_opens_nothing(self):
        opened = []
        c = ml.defaults()
        link = ml.MeshtasticLink(lambda: c, opener=lambda p: opened.append(p), cfg_ttl=0)
        self.links.append(link)
        time.sleep(0.3)
        self.assertEqual((link.status()["state"], opened), ("off", []))
        link.event("drones", "x")
        self.assertEqual(link.status()["queued"], 0)

    def test_test_message_goes_out_as_a_text_packet_on_the_channel(self):
        link, radio = self.link(cfg())
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        self.assertEqual(link.test(), (True, "queued"))
        self.assertTrue(wait(lambda: radio.texts()))
        m = radio.texts()[0]
        self.assertEqual((m["to"], m["channel"], m["text"], m["hop"]), (mt.BROADCAST, 1, ml.TEST_TEXT, 3))
        self.assertNotEqual(m["id"], 0)
        st = link.status()
        self.assertEqual((st["sent"], st["failed"], st["queued"]), (1, 0, 0))
        self.assertIsNotNone(st["last"])

    def test_test_is_refused_while_off_and_before_the_radio_answers(self):
        link, _ = self.link(cfg(enabled=False))
        self.assertEqual(link.test(), (False, "turn the Meshtastic link on first"))
        link2, _ = self.link(cfg(), radio=self.radio(silent=True), handshake_wait=5)
        time.sleep(0.2)
        self.assertEqual(link2.test(), (False, "the radio is not connected"))

    def test_the_public_channel_is_never_used(self):
        link, radio = self.link(cfg(channel=0))
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        ok, why = link.test()
        self.assertFalse(ok)
        self.assertIn("public channel", why)
        self.config["send"]["drones"] = True
        link.event("drones", "UAS-1")
        self.assertTrue(wait(lambda: link.status()["failed"] == 1))
        self.assertIn("public channel", link.status()["error"])
        self.assertEqual(radio.texts(), [])

    def test_a_channel_the_radio_does_not_have_is_refused(self):
        link, _ = self.link(cfg(channel=2))
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        self.assertEqual(link.test(), (False, "channel 2 is not on the radio"))

    def test_events_are_batched_and_spaced_out(self):
        c = cfg()
        c["send"] = {"new_devices": True, "drones": True, "lost_nodes": False, "nodes": False}
        link, radio = self.link(c, kind_gap=0.6, global_gap=0.25)
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        for t in ("Flock BLE at North", "Flock BLE at North", "Detector at Ridge"):
            link.event("new_devices", t)
        link.event("drones", "UAS-1")
        link.event("lost_nodes", "ignored: this type is off")
        self.assertTrue(wait(lambda: len(radio.texts()) == 2))
        self.assertEqual(radio.texts()[0]["text"], "OUI-APEX new devices: Flock BLE at North x2; Detector at Ridge")
        self.assertEqual(radio.texts()[1]["text"], "OUI-APEX drones: UAS-1")
        gap = radio.stamps[radio.rx.index(radio.texts()[1])] - radio.stamps[radio.rx.index(radio.texts()[0])]
        self.assertGreaterEqual(gap, 0.2)
        link.event("new_devices", "Camera at Gate")
        link.event("new_devices", "Camera at Gate")
        time.sleep(0.25)
        self.assertEqual(len(radio.texts()), 2)
        self.assertTrue(wait(lambda: len(radio.texts()) == 3, 3))
        self.assertEqual(radio.texts()[2]["text"], "OUI-APEX new devices: Camera at Gate x2")
        first, third = (radio.stamps[radio.rx.index(radio.texts()[i])] for i in (0, 2))
        self.assertGreaterEqual(third - first, 0.55)

    def test_each_recipient_gets_the_message_too(self):
        link, radio = self.link(cfg(recipients=["!0b0c0d0e"]))
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        link.test()
        self.assertTrue(wait(lambda: len(radio.texts()) == 2))
        self.assertEqual([m["to"] for m in radio.texts()], [mt.BROADCAST, PEER])
        self.assertEqual({m["text"] for m in radio.texts()}, {ml.TEST_TEXT})
        self.assertEqual(link.status()["sent"], 2)

    def test_messages_the_radio_hears_land_in_the_inbox(self):
        link, radio = self.link(cfg())
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        radio.inject_text(PEER, "all quiet\x00 é", channel=1)
        radio.inject_text(0x0DEADBEE, "who is this", channel=0)
        radio.inject_text(ME, "my own echo")
        self.assertTrue(wait(lambda: link.status()["heard"] == 2))
        inbox = link.status()["inbox"]
        self.assertEqual([m["text"] for m in inbox], ["who is this", "all quiet  é"])
        self.assertEqual((inbox[1]["from"], inbox[1]["name"], inbox[1]["channel"]), ("!0b0c0d0e", "North Gate", 1))
        self.assertEqual((inbox[0]["from"], inbox[0]["name"]), ("!0deadbee", ""))

    def test_the_inbox_keeps_the_last_50(self):
        link, radio = self.link(cfg())
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        for i in range(60):
            radio.inject_text(PEER, f"m{i}")
        self.assertTrue(wait(lambda: link.status()["heard"] == 60))
        inbox = link.status()["inbox"]
        self.assertEqual((len(inbox), inbox[0]["text"], inbox[-1]["text"]), (50, "m59", "m10"))

    def test_heartbeats_keep_the_serial_link_awake(self):
        link, radio = self.link(cfg(), heartbeat=0.15)
        self.assertTrue(wait(lambda: sum(m["kind"] == "heartbeat" for m in radio.rx) >= 2))

    def test_a_radio_that_never_answers_is_reported_and_retried(self):
        link, radio = self.link(cfg(), radio=self.radio(silent=True), handshake_wait=0.2)
        self.assertTrue(wait(lambda: link.status()["state"] == "retrying"))
        self.assertIn("did not answer", link.status()["error"])
        self.assertGreaterEqual(radio.handshakes, 2)

    def test_a_dropped_connection_is_reopened_and_the_handshake_repeated(self):
        first, second = self.radio(), self.radio()
        feed = iter([first, second])
        c = cfg()
        link = ml.MeshtasticLink(lambda: c, opener=lambda p: next(feed).transport(), kind_gap=0.4, global_gap=0.05,
                                 retry=(0.05, 0.1), cfg_ttl=0)
        self.links.append(link)
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        first.hang_up()
        self.assertTrue(wait(lambda: second.handshakes == 1))
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        link.test()
        self.assertTrue(wait(lambda: second.texts()))

    def test_a_tcp_target_connects_to_the_radio_on_its_port(self):
        srv = socket.socket()
        srv.bind(("127.0.0.1", 0))
        srv.listen(1)
        self.addCleanup(srv.close)
        port = srv.getsockname()[1]
        c = cfg(port=f"tcp:127.0.0.1:{port}")
        link = ml.MeshtasticLink(lambda: c, kind_gap=0.4, global_gap=0.05, cfg_ttl=0)
        self.links.append(link)
        conn, _ = srv.accept()
        radio = FakeRadio(sock=conn)
        self.radios.append(radio)
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        link.test()
        self.assertTrue(wait(lambda: radio.texts()))
        self.assertEqual(radio.texts()[0]["text"], ml.TEST_TEXT)

    def test_a_connection_that_cannot_open_says_why(self):
        def refuse(port):
            raise ConnectionRefusedError("connection refused")
        c = cfg(port="tcp:192.0.2.7")
        link = ml.MeshtasticLink(lambda: c, opener=refuse, retry=(0.05, 0.1), cfg_ttl=0)
        self.links.append(link)
        self.assertTrue(wait(lambda: link.status()["state"] == "retrying"))
        self.assertEqual(link.status()["error"], "connection refused")

    def test_a_reboot_notice_repeats_the_handshake(self):
        link, radio = self.link(cfg())
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        radio.reboot()
        self.assertTrue(wait(lambda: radio.handshakes == 2))
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))

    def test_switching_the_link_off_closes_it(self):
        link, radio = self.link(cfg())
        self.assertTrue(wait(lambda: link.status()["state"] == "connected"))
        self.config = cfg(enabled=False)
        self.assertEqual(link.status()["state"], "off")
        self.assertTrue(wait(lambda: link.tr is None))
        self.assertEqual(radio.handshakes, 1)


@unittest.skipUnless(HAVE_FLASK, "flask is not installed")
class RoutesTest(unittest.TestCase):
    PORT = 5077
    BASE = "http://127.0.0.1:5077"
    LAN = {"REMOTE_ADDR": "192.0.2.9"}

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        old = sys.argv
        sys.argv = ["ouispymesh.py", "--demo", "--db", os.path.join(cls.tmp.name, "t.db")]
        try:
            cls.om = importlib.import_module("ouispymesh")
        finally:
            sys.argv = old
        cls.om.tokens = access.TokenStore(os.path.join(cls.tmp.name, "tok"))
        cls.token = cls.om.tokens.create()
        cls.client = cls.om.app.test_client()

    @classmethod
    def tearDownClass(cls):
        cls.om.mesh.stop()
        cls.tmp.cleanup()

    def setUp(self):
        self.om.mesh.stop_evt.clear()
        self.radio = FakeRadio()
        self.om.store.set_setting("meshtastic", ml.defaults())
        self.om.mesh.opener = lambda port: self.radio.transport()
        self.om.mesh.outbox.kind_gap, self.om.mesh.global_gap, self.om.mesh.cfg_ttl = 0.3, 0.05, 0
        self.om.mesh.retry = (0.05, 0.1)
        if not self.om.mesh.thread.is_alive():
            self.om.mesh.thread = threading.Thread(target=self.om.mesh._run, daemon=True)
            self.om.mesh.thread.start()

    def tearDown(self):
        self.om.store.set_setting("meshtastic", ml.defaults())
        self.om.mesh.stop_evt.set()
        self.om.mesh.thread.join(3)
        self.radio.hang_up()

    def call(self, method, path, body=None, token=None, lan=False, origin=None):
        headers = {"Origin": origin} if origin else {}
        return self.client.open(path, method=method, json=body, base_url=self.BASE, headers=headers,
                                query_string={"token": token} if token else None,
                                environ_base=self.LAN if lan else {})

    def test_settings_and_test_are_refused_from_another_device_without_the_token(self):
        body = {"meshtastic": {"enabled": True, "port": "tcp:192.0.2.7"}}
        self.assertEqual(self.call("POST", "/api/settings", body, lan=True).status_code, 401)
        self.assertEqual(self.call("POST", "/api/settings", body, token="wrong", lan=True).status_code, 401)
        self.assertEqual(self.call("POST", "/api/meshtastic/test", {}, lan=True).status_code, 401)
        self.assertEqual(self.call("GET", "/api/meshtastic", lan=True).status_code, 401)
        self.assertEqual(self.om.settings()["meshtastic"], ml.defaults())

    def test_a_page_on_another_site_cannot_change_it_even_from_this_computer(self):
        body = {"meshtastic": {"enabled": True, "port": "tcp:192.0.2.7"}}
        r = self.call("POST", "/api/settings", body, origin="https://evil.example")
        self.assertEqual(r.status_code, 403)
        self.assertEqual(self.om.settings()["meshtastic"], ml.defaults())

    def test_the_token_holder_can_set_a_radio_port_and_bad_ones_are_refused(self):
        ok = self.call("POST", "/api/settings", {"meshtastic": {"port": "/dev/ttyUSB0", "channel": 1}},
                       token=self.token, lan=True)
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(ok.get_json()["meshtastic"]["port"], "/dev/ttyUSB0")
        for bad in ("/etc/passwd", "../x", "file:///etc/hosts"):
            r = self.call("POST", "/api/settings", {"meshtastic": {"port": bad}}, token=self.token, lan=True)
            self.assertEqual(r.status_code, 400, bad)
            self.assertIn("Meshtastic", r.get_json()["error"])
        self.assertEqual(self.om.settings()["meshtastic"]["port"], "/dev/ttyUSB0")

    def test_the_radio_cannot_take_the_boards_port(self):
        self.om.store.set_setting("serial_port", "/dev/ttyACM0")
        try:
            r = self.call("POST", "/api/settings", {"meshtastic": {"port": "/dev/ttyACM0"}})
            self.assertEqual(r.status_code, 400)
            r = self.call("POST", "/api/settings", {"meshtastic": {"enabled": True, "port": "/dev/ttyUSB0"}})
            self.assertEqual(r.status_code, 200)
            r = self.call("POST", "/api/settings", {"serial_port": "/dev/ttyUSB0"})
            self.assertEqual(r.status_code, 400)
        finally:
            self.om.store.set_setting("serial_port", "auto")

    def test_the_test_is_refused_until_the_radio_is_connected(self):
        r = self.call("POST", "/api/meshtastic/test", {})
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.get_json()["error"], "turn the Meshtastic link on first")

    def test_from_switch_on_to_a_message_on_the_fake_radio(self):
        on = {"meshtastic": {"enabled": True, "port": "tcp:192.0.2.7", "channel": 1,
                             "send": {"new_devices": True, "drones": False, "lost_nodes": True, "nodes": True}}}
        self.assertEqual(self.call("POST", "/api/settings", on, token=self.token, lan=True).status_code, 200)
        self.assertTrue(wait(lambda: self.call("GET", "/api/meshtastic").get_json()["state"] == "connected"))
        info = self.call("GET", "/api/meshtastic").get_json()
        self.assertEqual(info["config"]["port"], "tcp:192.0.2.7")
        self.assertEqual(info["channel_name"], "Fleet")
        self.assertEqual(info["radio"], "!0a1b2c3d")
        self.assertEqual(self.call("POST", "/api/meshtastic/test", {}).get_json(), {"ok": True, "queued": True})
        self.assertTrue(wait(lambda: self.radio.texts()))
        self.assertEqual(self.radio.texts()[0]["text"], ml.TEST_TEXT)
        self.om.store.update_node("A1B2", alias="North Gate")
        self.om.emit("det", {"mac": "AA:BB:CC:00:00:01", "node": "A1B2", "descr": "Flock BLE", "is_new": True})
        self.om.emit("drone", {"mac": "AA:BB:CC:00:00:02", "id": "UAS-9"})
        self.om.emit("node_event", {"id": "C3D4", "event": "offline"})
        self.om.emit("node_event", {"id": "C3D4", "event": "online"})
        self.assertTrue(wait(lambda: len(self.radio.texts()) == 4, 8))
        sent = [m["text"] for m in self.radio.texts()[1:]]
        self.assertIn("OUI-APEX new devices: Flock BLE at North Gate", sent)
        self.assertIn("OUI-APEX lost nodes seen again: C3D4", sent)
        self.assertTrue(any(s.startswith("OUI-APEX nodes: ") and "dropped" in s and "joined" in s for s in sent))
        self.assertFalse(any("UAS-9" in s for s in sent))
        link = self.call("GET", "/api/link").get_json()["settings"]["meshtastic"]
        self.assertEqual((link["enabled"], link["state"], link["sent"]), (True, "connected", 4))
        self.assertNotIn("inbox", link)

    def test_heard_messages_show_in_the_api(self):
        on = {"meshtastic": {"enabled": True, "port": "tcp:192.0.2.7"}}
        self.call("POST", "/api/settings", on)
        self.assertTrue(wait(lambda: self.call("GET", "/api/meshtastic").get_json()["state"] == "connected"))
        self.radio.inject_text(PEER, "<b>hello</b>")
        self.assertTrue(wait(lambda: self.call("GET", "/api/meshtastic").get_json()["heard"] == 1))
        row = self.call("GET", "/api/meshtastic").get_json()["inbox"][0]
        self.assertEqual((row["from"], row["name"], row["text"]), ("!0b0c0d0e", "North Gate", "<b>hello</b>"))


if __name__ == "__main__":
    unittest.main()
