# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""Board link framing, decoders and the live source against a fake board: python -m unittest discover -s tests"""
import os
import struct
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import board_decode as bd  # noqa: E402
import board_link as bl  # noqa: E402
from board_source import BoardSource, detection_to_fleet  # noqa: E402
from fakeboard import FakeBoard, detection, mesh_status  # noqa: E402
from fleet import Fleet  # noqa: E402
from store import Store  # noqa: E402


def wait(cond, secs=3.0):
    end = time.time() + secs
    while time.time() < end:
        if cond():
            return True
        time.sleep(0.02)
    return False


class FrameTest(unittest.TestCase):
    def test_crc_matches_ccitt_false_vector(self):
        self.assertEqual(bl.crc16(b"123456789"), 0x29B1)

    def test_frame_survives_log_text_and_split_delivery(self):
        frame = bl.encode(bl.T.NOTIFY, 0x10, bytes([1, 2, 3, 0xA5, 0x5A]))
        stream = b"[HB] tx id=ABCD\n" + frame + b"[WD] scan done\n"
        p, got = bl.FrameParser(), []
        for i in range(0, len(stream), 5):
            got += p.add(stream[i:i + 5])
        self.assertEqual(got, [(bl.T.NOTIFY, 0x10, bytes([1, 2, 3, 0xA5, 0x5A]))])

    def test_false_sync_does_not_swallow_next_frame(self):
        real = bl.encode(bl.T.WRITE_ACK, 2, b"\0")
        fake = bytes([0xA5, 0x5A, bl.T.NOTIFY, 0x10, 0, 5, 0, 9, 9, 9, 9, 9, 0, 0])
        p = bl.FrameParser()
        self.assertEqual(p.add(fake + real), [(bl.T.WRITE_ACK, 2, b"\0")])
        self.assertEqual(p.crc_errors, 1)

    def test_corrupt_frame_dropped_and_counted(self):
        f = bytearray(bl.encode(bl.T.NOTIFY, 0x10, b"\7\7\7"))
        f[8] ^= 0xFF
        p = bl.FrameParser()
        self.assertEqual(p.add(bytes(f)), [])
        self.assertEqual(p.crc_errors, 1)

    def test_oversize_payload_refused(self):
        with self.assertRaises(ValueError):
            bl.encode(bl.T.WRITE, 2, bytes(bl.MAX_PAYLOAD + 1))


class DecodeTest(unittest.TestCase):
    def test_node_ids(self):
        self.assertEqual(bd.canonical_node_id("OUISPY-a1b2"), "A1B2")
        self.assertEqual(bd.canonical_node_id("1234567"), "4567")
        self.assertEqual(bd.canonical_node_id("zz"), "")
        self.assertEqual(bd.canonical_node_id("OUISPY-GGGG"), "")

    def test_device_info(self):
        i = bd.device_info(b"0.7.0\x00OUISPY-A1B2\x00xiao_s3\x00mgr\x00150000\x00proto=1\x00boot=3")
        self.assertEqual((i["fw"], i["id"], i["board"], i["role"], i["proto"]), ("0.7.0", "A1B2", "xiao_s3", "mgr", 1))

    def test_detector_detection(self):
        ext = bytes([1]) + b"Axon body cam".ljust(32, b"\0") + bytes([87])
        d = bd.decode_detection(detection(engine=0, method=8, source=b"C3D4", ext=ext))
        self.assertEqual((d["engine"], d["method"], d["mac"], d["rssi"], d["source"]),
                         ("detector", "axon", "0A:1B:2C:3D:4E:5F", -60, "C3D4"))
        self.assertEqual((d["desc"], d["confidence"]), ("Axon body cam", 87))

    def test_wardrive_access_point(self):
        ext = b"MyNetwork".ljust(33, b"\0") + bytes([3]) + b"".ljust(21, b"\0")
        d = bd.decode_detection(detection(engine=6, method=0, ext=ext))
        self.assertEqual((d["method"], d["ssid"], d["auth"]), ("wifi_ap", "MyNetwork", 3))

    def test_sky_spy_remote_id(self):
        ext = bytearray(136)
        ext[0:5] = b"UAS-1"
        ext[21:25] = b"OP-9"
        struct.pack_into("<d", ext, 42, 10.0)
        struct.pack_into("<d", ext, 50, 20.0)
        struct.pack_into("<hhhh", ext, 58, 120, 80, 5, 90)
        struct.pack_into("<dd", ext, 66, 10.001, 20.001)
        d = bd.decode_detection(detection(engine=4, method=0, ext=bytes(ext)))
        o = d["odid"]
        self.assertEqual((o["id"], o["op"], o["lat"], o["lon"], o["alt"], o["hagl"], o["spd"], o["hdg"]),
                         ("UAS-1", "OP-9", 10.0, 20.0, 120, 80, 5, 90))
        self.assertEqual((o["plat"], o["plon"]), (10.001, 20.001))

    def test_short_detection_rejected(self):
        with self.assertRaises(ValueError):
            bd.decode_detection(b"\0\1\2")

    def test_mesh_status(self):
        raw = mesh_status([("A1B2", 1, 1, 0x000700, 1, 41), ("C3D4", 0, 3, 0x000700, 3, -128)],
                          details=[("C3D4", 0x000700, 3, 3600, 12, 3, 2, 3)],
                          signal=[("A1B2", [("C3D4", -70)]), ("C3D4", [("A1B2", None)])])
        s = bd.decode_mesh_status(raw)
        self.assertEqual((s["enabled"], s["rx"], s["tx"], s["key_failures"]), (True, 10, 5, 0))
        self.assertEqual([(n["id"], n["role"], n["board"], n["temp"]) for n in s["live"]],
                         [("A1B2", "manager", "xiao_s3", 41), ("C3D4", "node", "xiao_c5", None)])
        self.assertEqual(s["details"], [{"id": "C3D4", "fw": 0x700, "board": "xiao_c5", "up": 3600,
                                         "filter_macs": 12, "filter_uuids": 3, "peers": 2, "age": 30}])
        self.assertEqual(s["signal"], [{"id": "A1B2", "hears": [{"id": "C3D4", "rssi": -70}]},
                                       {"id": "C3D4", "hears": [{"id": "A1B2", "rssi": None}]}])
        self.assertEqual(bd.firmware_text(0x000702), "0.7.2")

    def test_short_status_is_empty(self):
        self.assertEqual(bd.decode_mesh_status(b"\1\2")["live"], [])

    def test_control_encoders_match_the_app(self):
        self.assertEqual(bd.encode_status_request(), bytes([0x23, 0]))
        self.assertEqual(bd.encode_status_request("C3D4"), bytes([0x23, 0, 0xFE]) + b"C3D4\0")
        self.assertEqual(bd.encode_identify("C3D4", 10), bytes([0x20, 0, 0xFE]) + b"C3D4\0" + bytes([10, 3]))
        self.assertEqual(bd.encode_reboot(), bytes([0x22, 0, 0xC0, 0xDE]))
        with self.assertRaises(ValueError):
            bd.encode_reboot("nope")


class LinkSessionTest(unittest.TestCase):
    def setUp(self):
        self.board = FakeBoard()
        self.notes = []
        self.sess = bl.LinkSession(self.board.transport(), on_notify=lambda c, p: self.notes.append((c, p)))

    def tearDown(self):
        self.sess.close()
        self.board.close()

    def test_hello_read_subscribe_write_notify(self):
        self.sess.start()
        self.assertIn(bl.CHR_MESH_STATUS, self.sess.ids)
        self.assertEqual(bd.device_info(self.sess.read(bl.CHR_DEVICE_INFO))["id"], "A1B2")
        self.sess.subscribe(bl.CHR_DETECTION_EVENTS)
        self.assertIn(bl.CHR_DETECTION_EVENTS, self.board.subscribed)
        self.sess.write(bl.CHR_ENGINE_CONTROL, bd.encode_status_request())
        self.assertEqual(self.board.writes[-1], (bl.CHR_ENGINE_CONTROL, bytes([0x23, 0])))
        self.board.notify(bl.CHR_DETECTION_EVENTS, b"abc")
        self.assertTrue(wait(lambda: self.notes))
        self.assertEqual(self.notes[0], (bl.CHR_DETECTION_EVENTS, b"abc"))

    def test_refused_write_and_read_raise(self):
        self.sess.start()
        self.board.refuse_writes = True
        with self.assertRaises(bl.LinkError):
            self.sess.write(bl.CHR_ENGINE_CONTROL, b"x")
        with self.assertRaises(bl.LinkError):
            self.sess.read(0x7777)

    def test_hello_times_out_on_a_silent_port(self):
        self.board.stop = True
        time.sleep(0.4)
        self.sess.HELLO_TIMEOUT = 0.3
        with self.assertRaises(bl.LinkError):
            self.sess.start()


class SourceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(os.path.join(self.tmp.name, "t.db"))
        self.events = []
        self.fleet = Fleet(self.store, lambda e, p: self.events.append((e, p)))
        self.board = FakeBoard()
        self.src = BoardSource(self.fleet, lambda: None, "auto", get_poll=lambda: 0,
                               transport_factory=self.board.transport)

    def tearDown(self):
        self.src.stop()
        self.board.close()
        self.tmp.cleanup()

    def nodes(self):
        return {n["id"]: n for n in self.fleet.snapshot()["nodes"]}

    def test_detections_and_mesh_status_reach_the_fleet(self):
        self.src.start()
        self.assertTrue(wait(lambda: self.src.status().get("connected")))
        self.assertEqual(self.fleet.home_id, "A1B2")
        self.assertTrue(wait(lambda: bl.CHR_DETECTION_EVENTS in self.board.subscribed
                             and bl.CHR_MESH_STATUS in self.board.subscribed))
        self.assertTrue(wait(lambda: (bl.CHR_ENGINE_CONTROL, bytes([0x23, 0])) in self.board.writes))
        self.board.notify(bl.CHR_MESH_STATUS, mesh_status(
            [("A1B2", 1, 1, 0x700, 1, 41), ("C3D4", 0, 1, 0x700, 3, 30)],
            details=[("C3D4", 0x700, 3, 3600, 12, 3, 2, 3)], signal=[("A1B2", [("C3D4", -70)])]))
        self.assertTrue(wait(lambda: (self.nodes().get("C3D4") or {}).get("cfg")))
        n = self.nodes()["C3D4"]
        self.assertTrue(n["online"])
        self.assertEqual(n["rssi"], -70)
        self.assertEqual((n["cfg"]["fw"], n["cfg"]["up"], n["cfg"]["filters"]), ("0.7.0", 3600, 12))
        self.assertTrue(self.nodes()["A1B2"]["is_home"])
        ext = bytes([1]) + b"Axon body cam".ljust(32, b"\0") + bytes([80])
        self.board.notify(bl.CHR_DETECTION_EVENTS, detection(engine=0, method=8, source=b"C3D4", ext=ext))
        self.assertTrue(wait(lambda: any(e == "det" for e, _ in self.events)))
        det = [p for e, p in self.events if e == "det"][0]
        self.assertEqual((det["node"], det["mac"], det["type"], det["dom"]), ("C3D4", "0A:1B:2C:3D:4E:5F", "AXON", "ble"))
        self.assertEqual(self.store.query_detections(limit=5)[0], 1)

    def test_drone_goes_to_the_drone_tracker(self):
        fed = []

        class D:
            def feed(self, obj, source, home):
                fed.append((obj, source, home))
        self.fleet.drones = D()
        ext = bytearray(136)
        ext[0:5] = b"UAS-1"
        struct.pack_into("<dd", ext, 42, 10.0, 20.0)
        self.src.start()
        self.assertTrue(wait(lambda: self.src.status().get("connected")))
        self.board.notify(bl.CHR_DETECTION_EVENTS, detection(engine=4, ext=bytes(ext)))
        self.assertTrue(wait(lambda: fed))
        self.assertEqual((fed[0][0]["id"], fed[0][0]["lat"], fed[0][1], fed[0][2]), ("UAS-1", 10.0, "rid", "A1B2"))

    def test_control_goes_down_the_link(self):
        self.src.start()
        self.assertTrue(wait(lambda: self.src.status().get("connected")))
        self.assertTrue(self.src.control(bd.encode_identify("C3D4", 5)))
        self.assertIn((bl.CHR_ENGINE_CONTROL, bd.encode_identify("C3D4", 5)), self.board.writes)

    def test_wifi_detection_is_marked_wifi(self):
        d = bd.decode_detection(detection(engine=2, method=0, channel=11))
        f = detection_to_fleet(d, "A1B2")
        self.assertEqual((f["dom"], f["node"], f["type"], f["info"]), ("wifi", "A1B2", "OUI_ADDR1", {"ch": 11}))


if __name__ == "__main__":
    unittest.main()
