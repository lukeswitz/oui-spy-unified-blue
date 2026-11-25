# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

import datetime
import json
import os
import sys
import tempfile
import types

sys.modules["pytz"] = types.SimpleNamespace(UTC=datetime.timezone.utc)
sys.path.insert(0, sys.argv[1])
from OpenDroneID.encoder import OpenDroneID
from OpenDroneID.json_parser import json_to_packets
from OpenDroneID.Messages.definitions import ProtoVersions

here = os.path.dirname(os.path.abspath(__file__))
drone = [[
    {"Basic ID": {"protocol_version": "F3411.19", "id_type": "Serial Number (ANSI/CTA-2063-A)",
                  "id": "TESTDRONE1234567890", "ua_type": "Helicopter (or Multirotor)"}},
    {"Basic ID": {"protocol_version": "F3411.19", "id_type": "CAA Assigned Registration ID",
                  "id": "CAAREG0001", "ua_type": "Helicopter (or Multirotor)"}},
    {"Location Vector": {"protocol_version": "F3411.19", "op_status": "Airborne", "height_type": "Above Takeoff",
                         "ew_dir_segment": "East", "speed_multiplier": "0.25",
                         "coord": {"direction": 90, "speed": 23, "vert_speed": 126,
                                   "latitude": 514779000, "longitude": -15000,
                                   "pressure_altitude": 0, "geodetic_altitude": 2201, "height_agl": 0,
                                   "horizontal_accuracy": "<1 m", "vertical_accuracy": "<10 m",
                                   "baro_accuracy": "<10 m", "speed_accuracy": "<0.3 m/s",
                                   "timestamp": 65535, "timestamp_accuracy": 0}}},
    {"Self ID": {"protocol_version": "F3411.19", "text_type": "Text Description", "text": "host test"}},
    {"System": {"protocol_version": "F3411.19", "classification_type": "EU", "operator_location_type": "Takeoff",
                "latitude": 514780000, "longitude": -16000, "area_count": 1, "area_radius": 0,
                "area_ceiling": 2000, "area_floor": 2000, "ua_classification_category_type": "Open",
                "ua_classification_category_class": "Class 1", "geodetic_altitude": 2170, "timestamp": 0}},
    {"Operator ID": {"protocol_version": "F3411.19", "id_type": "Operator ID", "id": "OPERATOR01"}},
]]
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    json.dump(drone, f)
    path = f.name
packets = json_to_packets(path)
os.unlink(path)
msgs = packets["TESTDRONE1234567890"][0]
pack_a = OpenDroneID(protocol_version=ProtoVersions.F3411_19.value, msgs=msgs).parse()
empty_serial = bytes([0x02, 0x10]) + bytes(23)
msgs_b = [empty_serial] + [m for m in msgs if m[0] >> 4 != 0 or m[2:12] == b"CAAREG0001"]
pack_b = OpenDroneID(protocol_version=ProtoVersions.F3411_19.value, msgs=msgs_b).parse()


def ble_adv(pack):
    data = bytes([0x16]) + (0xFFFA).to_bytes(2, "little") + bytes([0x0D, 0x01]) + pack
    return bytes([len(data)]) + data


def beacon(pack):
    hdr = bytes([0x80, 0x00, 0x00, 0x00]) + b"\xff" * 6 + bytes([0x02, 0, 0, 0, 0, 0x07]) * 2 + bytes(2)
    ie_body = bytes([0xFA, 0x0B, 0xBC, 0x0D, 0x01]) + pack
    return hdr + bytes(12) + bytes([0xDD, len(ie_body)]) + ie_body


with open(os.path.join(here, "vectors.h"), "w") as f:
    for name, b in [("BLE_A", ble_adv(pack_a)), ("BLE_B", ble_adv(pack_b)),
                    ("BEACON_A", beacon(pack_a)), ("BEACON_B", beacon(pack_b))]:
        f.write("static const uint8_t %s[] = {%s};\n" % (name, ",".join("0x%02x" % x for x in b)))
