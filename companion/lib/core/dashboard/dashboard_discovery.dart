// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';
import 'package:oui_spy/core/dashboard/dashboard_api.dart';

abstract class DashboardDiscovery {
  Future<DashboardEndpoint?> find();
}

/// Looks for `_ouispy._tcp` on the local network with multicast DNS. The dashboard announces itself
/// only when it was started with `--lan --advertise`. This runs only while the user has turned
/// **Find on this network** on.
class MdnsDashboardDiscovery implements DashboardDiscovery {
  static const service = '_ouispy._tcp.local';
  static const lookupTime = Duration(seconds: 4);

  @override
  Future<DashboardEndpoint?> find() async {
    final client = MDnsClient();
    try {
      await client.start();
      await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(service),
          timeout: lookupTime)) {
        await for (final srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
            timeout: lookupTime)) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
              timeout: lookupTime)) {
            if (ip.address.type == InternetAddressType.IPv4) {
              return DashboardEndpoint(ip.address.address, srv.port);
            }
          }
        }
      }
      return null;
    } on SocketException {
      return null;
    } finally {
      client.stop();
    }
  }
}
