// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/atak/atak_connector.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';

class AtakSection extends ConsumerStatefulWidget {
  const AtakSection({super.key});

  @override
  ConsumerState<AtakSection> createState() => _AtakSectionState();
}

class _AtakSectionState extends ConsumerState<AtakSection> {
  late final TextEditingController _host;
  late final TextEditingController _port;

  @override
  void initState() {
    super.initState();
    final s = ref.read(atakConnectorProvider);
    _host = TextEditingController(text: s.host);
    _port = TextEditingController(text: '${s.port}');
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _saveAddress() async {
    final c = ref.read(atakConnectorProvider.notifier);
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? -1;
    if (InternetAddress.tryParse(host) == null || !AtakSettings.validPort(port)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Enter an IP address and a port from 1 to 65535')),
      );
      return;
    }
    await c.update(ref.read(atakConnectorProvider).copyWith(host: host, port: port));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('ATAK address saved: $host:$port')));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(atakConnectorProvider);
    final c = ref.read(atakConnectorProvider.notifier);
    final t = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigToggleRow(
          icon: Icons.map_outlined,
          label: 'Send to ATAK',
          subtitle: 'Catches and Remote ID drones as map markers, over UDP',
          color: AppTheme.accent,
          value: s.enabled,
          notify: false,
          onChanged: (v) => c.update(s.copyWith(enabled: v)),
        ),
        if (s.enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _host,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Address', helperText: '127.0.0.1 is ATAK on this phone'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'UDP port'),
                  ),
                ),
                IconButton(icon: const Icon(Icons.check), tooltip: 'Save address', onPressed: _saveAddress),
              ],
            ),
          ),
          ConfigToggleRow(
            icon: Icons.wifi_tethering,
            label: 'Also send to the SA multicast group',
            subtitle: '239.2.3.1:6969. Every device on this Wi-Fi network can read it',
            color: AppTheme.warning,
            value: s.multicast,
            notify: false,
            onChanged: (v) => c.update(s.copyWith(multicast: v)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text('In ATAK, add a UDP network input on the same port.',
                style: TextStyle(color: t.textDim, fontSize: 13)),
          ),
        ],
      ],
    );
  }
}
