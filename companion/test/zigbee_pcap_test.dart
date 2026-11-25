// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/features/pcap/pcap_stats.dart';

void main() {
  test('pcap mode 2 is 802.15.4', () {
    expect(PcapMode.zigbee.index, 2);
    expect(PcapStats.empty.modeEnum, PcapMode.wifi);
    expect(PcapStats.empty.modeLabel, 'WIFI 802.11');
  });
}
