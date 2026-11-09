import 'dart:typed_data';

import 'fast_pair_models.dart';
import 'observation.dart';
import 'signature_engine.dart' show teslaIBeaconMfgPrefix;
import 'smarttag.dart';

class AdvField {
  final String label;
  final String value;
  const AdvField(this.label, this.value);
}

class RoleHint {
  final String bucket;
  final String label;
  final String reason;
  final int weight;
  const RoleHint(this.bucket, this.label, this.reason, this.weight);
}

class _Tlv {
  final int type;
  final Uint8List data;
  _Tlv(this.type, this.data);
}

class AdvPayloadDecoder {
  static const targetAtriusIBeaconMfgPrefix = '02155993A94C7D974DF79ABFE493BFD5D000';

  static List<AdvField> decodeManufacturer(MfgRecord record) {
    final bytes = hexToBytes(record.dataHex);
    if (bytes == null) return const [];
    switch (record.companyId) {
      case 0x004C:
        return _decodeApple(bytes);
      case 0x0006:
        return _decodeMicrosoft(bytes);
      case 0x0157:
        return _decodeAltBeacon(bytes);
      case 0x00E0:
        return [AdvField('Google manufacturer data', '${bytes.length} bytes')];
      default:
        return const [];
    }
  }

  static List<AdvField> decodeService(ServiceDataRecord record) {
    final bytes = hexToBytes(record.dataHex);
    if (bytes == null) return const [];
    switch (uuid16(record.uuid)) {
      case 0xFE2C:
        return _decodeFastPair(bytes);
      case 0xFEAA:
        return _decodeEddystone(bytes);
      case 0xFD5A:
        final tag = SmartTagAdv.parse(bytes);
        if (tag == null) return const [];
        return [
          AdvField('SmartTag', tag.stateLabel),
          AdvField('SmartTag privacy ID', tag.privacyId),
          AdvField('SmartTag UWB', tag.uwb ? 'yes' : 'no'),
        ];
      default:
        return const [];
    }
  }

  static List<RoleHint> roleHints(Observation device) {
    final out = <RoleHint>[];
    for (final rec in device.mfgRecords) {
      if (rec.companyId != 0x004C) continue;
      final bytes = hexToBytes(rec.dataHex);
      if (bytes == null) continue;
      for (final tlv in _appleTlvs(bytes)) {
        switch (tlv.type) {
          case 0x02:
            if (tlv.data.length >= 20) {
              final hex = _hexUpper(tlv.data);
              if (hex.startsWith(teslaIBeaconMfgPrefix) || hex.startsWith(teslaIBeaconMfgPrefix.substring(4))) {
                out.add(
                  const RoleHint(
                    'vehicle',
                    'a Tesla vehicle or phone-as-key',
                    'Tesla phone-key iBeacon UUID (iOS background find).',
                    8,
                  ),
                );
              } else if (hex.startsWith(targetAtriusIBeaconMfgPrefix) ||
                  hex.startsWith(targetAtriusIBeaconMfgPrefix.substring(4))) {
                out.add(
                  const RoleHint(
                    'beacon',
                    'an Atrius cart tag',
                    'Atrius cart-tag iBeacon. The advertisement does not name the store.',
                    8,
                  ),
                );
              } else {
                out.add(const RoleHint('beacon', 'an iBeacon', 'It broadcasts an Apple iBeacon signal.', 7));
              }
            }
          case 0x05:
            out.add(const RoleHint('phone', 'an iPhone or iPad offering AirDrop', 'It is offering AirDrop, which Apple phones and Macs do.', 5));
          case 0x07:
            final model = _airPodsModel(tlv.data);
            out.add(
              RoleHint(
                'audio-personal',
                model ?? 'AirPods or Beats headphones',
                model != null ? 'Apple Proximity Pairing: $model.' : 'Apple Proximity Pairing (AirPods / Beats).',
                8,
              ),
            );
          case 0x08:
            out.add(const RoleHint('siri', 'an Apple device that just heard “Hey Siri”', 'It sends the signal Apple devices use to coordinate "Hey Siri".', 6));
          case 0x09:
            out.add(const RoleHint('audio-speaker', 'an AirPlay speaker or Apple TV', 'It announces itself as an AirPlay target.', 5));
          case 0x0B:
            out.add(const RoleHint('wearable', 'an Apple Watch', 'It sends Magic Switch, which only a worn Apple Watch sends after losing its iPhone link.', 8));
          case 0x0C:
            out.add(const RoleHint('phone', 'an Apple device doing Handoff', 'It sends Apple Handoff signals, which an iPhone, iPad or Mac in use does.', 4));
          case 0x0D:
          case 0x0E:
            out.add(
              const RoleHint(
                'hotspot',
                'an iPhone/iPad offering Instant Hotspot',
                'Tethering-source advertisement.',
                6,
              ),
            );
          case 0x0F:
            out.add(RoleHint('phone', 'an Apple device (Nearby Action)', _nearbyActionReason(tlv.data), 4));
          case 0x10:
            out.add(RoleHint('phone', 'an iPhone / iPad / Mac (Nearby Info)', _nearbyInfoReason(tlv.data), 5));
          case 0x12:
            out.add(
              const RoleHint(
                'tag',
                'a Find My network radio',
                'Apple Offline Finding — AirTag, Find My accessory, or an Apple device locating itself.',
                4,
              ),
            );
        }
      }
    }
    for (final sd in device.serviceData) {
      switch (uuid16(sd.uuid)) {
        case 0xFE2C:
          final bytes = hexToBytes(sd.dataHex);
          if (bytes == null) continue;
          if (bytes.length == 3) {
            final m = FastPairModels.models[_modelId24(bytes)];
            out.add(
              m == null
                  ? RoleHint(
                      'audio-personal',
                      'a Fast Pair accessory (often earbuds or a speaker)',
                      'Google Fast Pair model 0x${_hex(_modelId24(bytes), 6)}, in pairing mode.',
                      6,
                    )
                  : RoleHint(
                      m.bucket,
                      m.name,
                      'Google Fast Pair model 0x${_hex(_modelId24(bytes), 6)} is listed as ${m.name}'
                      '${m.maker.isEmpty ? '' : ' by ${m.maker}'}. It is in pairing mode.',
                      8,
                    ),
            );
          } else {
            out.add(
              const RoleHint(
                'audio-personal',
                'a Fast Pair accessory already paired to someone',
                'Google Fast Pair account-key broadcast (not in pairing mode).',
                4,
              ),
            );
          }
        case 0xFEAA:
          final bytes = hexToBytes(sd.dataHex);
          final frame = (bytes == null || bytes.isEmpty) ? null : bytes[0];
          if (frame == 0x40 || frame == 0x41) {
            out.add(
              RoleHint(
                'tag',
                'a Google Find Hub tag',
                frame == 0x41 ? 'Find Hub separated (unwanted-tracking) frame.' : 'Find Hub nearby frame.',
                8,
              ),
            );
          } else {
            out.add(const RoleHint('beacon', 'an Eddystone beacon', 'It broadcasts a Google Eddystone beacon signal.', 6));
          }
        case 0xFD5A:
          final bytes = hexToBytes(sd.dataHex);
          final tag = bytes == null ? null : SmartTagAdv.parse(bytes);
          if (tag != null) {
            out.add(
              RoleHint(
                'tag',
                tag.separated ? 'a Samsung SmartTag away from its owner' : 'a Samsung SmartTag with its owner',
                'Samsung SmartTag Offline Finding frame: ${tag.stateLabel}.',
                8,
              ),
            );
          }
      }
    }
    return out;
  }

  static List<AdvField> _decodeApple(Uint8List bytes) {
    final tlvs = _appleTlvs(bytes);
    if (tlvs.isEmpty) return [AdvField('Apple payload', '${bytes.length} bytes (unparsed)')];
    final out = <AdvField>[];
    for (final tlv in tlvs) {
      out.add(AdvField('Apple Continuity type', '0x${_hex(tlv.type, 2)} · ${_appleTypeName(tlv.type)}'));
      out.addAll(switch (tlv.type) {
        0x02 => _decodeIBeacon(tlv.data),
        0x05 => _decodeAirDrop(tlv.data),
        0x06 => [AdvField('HomeKit', '${tlv.data.length} bytes of HomeKit setup data')],
        0x07 => _decodeAirPods(tlv.data),
        0x08 => _decodeHeySiri(tlv.data),
        0x09 => const [AdvField('AirPlay', 'This device is advertising as an AirPlay source or target.')],
        0x0A => const [AdvField('AirPlay', 'This device is advertising as an AirPlay source.')],
        0x0B => const [AdvField('Magic Switch', 'Apple Watch on a wrist that lost its iPhone link.')],
        0x0C =>
          tlv.data.length >= 14
              ? _decodeHandoff()
              : const [
                  AdvField('Instant Hotspot (looking)', 'This Apple device is searching for a paired phone’s hotspot.'),
                ],
        0x0D || 0x0E => _decodeTetherSource(tlv.data),
        0x0F => _decodeNearbyAction(tlv.data),
        0x10 => _decodeNearbyInfo(tlv.data),
        0x12 => _decodeFindMy(tlv.data),
        _ => [AdvField('Payload', '${tlv.data.length} bytes')],
      });
    }
    return out;
  }

  static List<_Tlv> _appleTlvs(Uint8List bytes) {
    final out = <_Tlv>[];
    var i = 0;
    while (i + 2 <= bytes.length) {
      final type = bytes[i];
      final len = bytes[i + 1];
      if (len <= 0 || i + 2 + len > bytes.length) break;
      out.add(_Tlv(type, Uint8List.sublistView(bytes, i + 2, i + 2 + len)));
      i += 2 + len;
    }
    return out;
  }

  static String _appleTypeName(int type) => switch (type) {
    0x02 => 'iBeacon',
    0x03 => 'AirPrint',
    0x05 => 'AirDrop',
    0x06 => 'HomeKit',
    0x07 => 'Proximity Pairing (AirPods / Beats)',
    0x08 => 'Hey Siri',
    0x09 => 'AirPlay',
    0x0A => 'AirPlay source',
    0x0B => 'Magic Switch (Watch)',
    0x0C => 'Handoff',
    0x0D || 0x0E => 'Instant Hotspot (source)',
    0x0F => 'Nearby Action',
    0x10 || 0x16 => 'Nearby Info',
    0x12 => 'Find My / Offline Finding',
    0x13 => 'Nearby Action (extended)',
    _ => 'unlisted',
  };

  static List<AdvField> _decodeIBeacon(Uint8List data) {
    final Uint8List body;
    if (data.length >= 22 && data[0] == 0x15) {
      body = Uint8List.sublistView(data, 1, 22);
    } else if (data.length >= 21) {
      body = Uint8List.sublistView(data, 0, 21);
    } else {
      return [AdvField('iBeacon', 'truncated (${data.length} bytes)')];
    }
    final uuid = _uuidFromBe(body, 0);
    final tx = body[20].toSigned(8);
    final teslaKey = hexOnly(uuid) == teslaIBeaconMfgPrefix.substring(4);
    return [
      AdvField(
        'iBeacon UUID',
        teslaKey ? '$uuid — Tesla phone-as-key (iOS background find). Not a mall beacon.' : uuid,
      ),
      AdvField('iBeacon major / minor', '${_u16be(body, 16)} / ${_u16be(body, 18)}'),
      AdvField('iBeacon calibrated TX', '$tx dBm at 1 m (used to estimate range)'),
    ];
  }

  static List<AdvField> _decodeAirDrop(Uint8List data) {
    if (data.length < 18) {
      return [AdvField('AirDrop', 'Someone nearby is offering AirDrop (${data.length} bytes).')];
    }
    return [
      const AdvField('AirDrop', 'Someone nearby has AirDrop receiving on. Hashes are truncated IDs, not names.'),
      AdvField('Apple ID hash (2 bytes)', _hexUpper(Uint8List.sublistView(data, 9, 11))),
    ];
  }

  static List<AdvField> _decodeAirPods(Uint8List data) {
    if (data.length < 5) return const [AdvField('AirPods', 'Proximity Pairing, truncated.')];
    final start = data[0] == 0x01 ? 1 : 0;
    if (data.length < start + 4) return const [AdvField('AirPods', 'Proximity Pairing.')];
    final model = (data[start] << 8) | data[start + 1];
    final status = data[start + 2];
    final batt = data[start + 3];
    final out = <AdvField>[
      AdvField('Product', _airPodsModelName(model) ?? 'Apple audio 0x${_hex(model, 4)}'),
      AdvField('Pod position', _airPodsStatus(status)),
      AdvField('Battery (left / right)', '${_nibblePct(batt & 0x0F)} / ${_nibblePct((batt >> 4) & 0x0F)}'),
    ];
    if (data.length > start + 4) {
      final ch = data[start + 4];
      final charging = [if (ch & 0x10 != 0) 'case', if (ch & 0x20 != 0) 'right', if (ch & 0x40 != 0) 'left'];
      out.add(AdvField('Case battery', _nibblePct(ch & 0x0F)));
      if (charging.isNotEmpty) out.add(AdvField('Charging', charging.join(', ')));
    }
    if (data.length > start + 6) out.add(AdvField('Color', _airPodsColor(data[start + 6])));
    return out;
  }

  static String? _airPodsModel(Uint8List data) {
    if (data.length < 4) return null;
    final start = data[0] == 0x01 ? 1 : 0;
    return _airPodsModelName((data[start] << 8) | data[start + 1]);
  }

  static String? _airPodsModelName(int id) => switch (id) {
    0x0220 => 'AirPods (1st generation)',
    0x0F20 => 'AirPods (2nd generation)',
    0x1320 => 'AirPods (3rd generation)',
    0x1920 => 'AirPods (4th generation)',
    0x1C20 => 'AirPods 4',
    0x0E20 => 'AirPods Pro',
    0x1420 => 'AirPods Pro (2nd generation)',
    0x2420 => 'AirPods Pro 2 (USB-C)',
    0x1F20 => 'AirPods Max',
    0x0A20 => 'Beats Solo3',
    0x0B20 => 'Powerbeats 3',
    0x0C20 => 'Beats Studio Buds',
    0x0D20 => 'Beats Fit Pro',
    0x1020 => 'Powerbeats Pro',
    0x1120 => 'Beats Studio Buds +',
    0x1220 => 'Beats Solo Pro',
    0x1720 => 'Beats Flex',
    0x1A20 => 'Beats Studio Pro',
    0x1B20 => 'Beats Fit Pro',
    0x0520 => 'BeatsX',
    0x0920 => 'Beats Studio³ Wireless',
    0x1620 => 'Beats Studio Buds +',
    0x2520 => 'Beats Solo 4',
    0x2620 => 'Beats Solo Buds',
    0x2D20 => 'AirPods Max 2',
    0x3820 => 'Beats 360',
    0x038F => 'Beats Studio Buds',
    _ => null,
  };

  static String _airPodsStatus(int s) => switch (s) {
    0x01 => 'One or both out of the case',
    0x02 => 'Case open',
    0x03 => 'Taken out / in-ear transition',
    0x05 => 'One in ear',
    0x09 => 'Both out, not in ear',
    0x0B => 'In-ear activity',
    0x11 || 0x13 => 'Both in ear',
    0x21 => 'One in ear (sharing?)',
    0x51 => 'Both in case, lid open',
    0x55 => 'Both in case, lid closed',
    0x75 => 'In case',
    _ => 'Status 0x${_hex(s, 2)}',
  };

  static String _airPodsColor(int v) => switch (v) {
    0x00 => 'White',
    0x01 => 'Black',
    0x02 => 'Red',
    0x03 => 'Blue',
    0x04 => 'Pink',
    0x05 => 'Gray',
    0x06 => 'Silver',
    0x07 => 'Gold',
    0x08 => 'Rose gold',
    0x09 => 'Space gray',
    0x0A => 'Dark blue',
    0x0B => 'Light blue',
    0x0C => 'Yellow',
    _ => '0x${_hex(v, 2)}',
  };

  static String _nibblePct(int n) {
    if (n >= 0 && n <= 9) return '${n * 10}%';
    if (n >= 10 && n <= 14) return '100%';
    if (n == 15) return 'unknown / not present';
    return '$n';
  }

  static List<AdvField> _decodeHeySiri(Uint8List data) {
    if (data.length < 6) return const [AdvField('Hey Siri', 'Siri was just triggered on a nearby Apple device.')];
    final klass = _u16be(data, 4);
    final device = switch (klass) {
      0x0002 => 'iPhone',
      0x0003 => 'iPad',
      0x0007 => 'HomePod',
      0x0009 => 'Mac',
      0x000A => 'Watch',
      _ => 'class 0x${_hex(klass, 4)}',
    };
    return [
      AdvField(
        'Hey Siri',
        'A $device just heard a Siri trigger. The packet carries a short voice hash, not the words.',
      ),
    ];
  }

  static List<AdvField> _decodeHandoff() => const [
    AdvField('Handoff', 'Continuity Handoff: a task can be continued on another Apple device. Payload is encrypted.'),
  ];

  static List<AdvField> _decodeTetherSource(Uint8List data) {
    if (data.length < 6) return const [AdvField('Instant Hotspot', 'An iPhone/iPad is offering a personal hotspot.')];
    final batt = data[2];
    final cell = _u16be(data, 3);
    final bars = data[5];
    final cellName = switch (cell) {
      0 || 6 => '4G',
      1 => '1xRTT',
      2 => 'GPRS',
      3 => 'EDGE',
      4 || 5 => '3G',
      7 => 'LTE',
      8 => '5G',
      _ => 'type $cell',
    };
    final b = StringBuffer('Paired iPhone/iPad hotspot');
    if (batt <= 100) b.write(' · phone battery $batt%');
    b.write(' · $cellName');
    if (bars <= 5) b.write(' · $bars/5 bars');
    return [AdvField('Instant Hotspot (offering)', b.toString())];
  }

  static List<AdvField> _decodeNearbyAction(Uint8List data) {
    if (data.isEmpty) return const [AdvField('Nearby Action', 'Apple Nearby Action')];
    return [AdvField('Nearby Action', _nearbyActionName(data.length >= 2 ? data[1] : data[0]))];
  }

  static String _nearbyActionReason(Uint8List data) =>
      data.length >= 2 ? 'Nearby Action: ${_nearbyActionName(data[1])}.' : 'Nearby Action advertisement.';

  static String _nearbyActionName(int a) => switch (a) {
    0x01 => 'Apple TV setup',
    0x04 => 'Mobile backup',
    0x05 => 'Watch setup',
    0x06 => 'Apple TV pair',
    0x08 => 'Wi-Fi password sharing (prompting nearby iPhones)',
    0x09 => 'iOS setup',
    0x0A => 'Repair',
    0x0B => 'Speaker setup',
    0x0C => 'Apple Pay',
    0x0D => 'Whole-home audio setup',
    0x0F => 'Answered a call',
    0x10 => 'Ended a call',
    0x13 => 'Remote AutoFill',
    0x14 => 'Companion Link proximity',
    0x17 => 'Remote display',
    _ => 'action 0x${_hex(a, 2)}',
  };

  static List<AdvField> _decodeNearbyInfo(Uint8List data) {
    if (data.isEmpty) return const [AdvField('Nearby Info', 'Apple device usage state.')];
    final status = data[0];
    final action = status & 0x0F;
    final flagsHi = (status >> 4) & 0x0F;
    final dataFlags = data.length > 1 ? data[1] : 0;
    final activity = switch (action) {
      0x00 => 'activity unknown',
      0x01 => 'activity reporting off',
      0x03 => 'idle (screen locked)',
      0x05 => 'audio playing, screen locked',
      0x07 => 'active (screen on)',
      0x09 => 'screen on, video playing',
      0x0A => 'Watch on wrist and unlocked',
      0x0B => 'recent interaction',
      0x0D => 'user is driving',
      0x0E => 'phone or FaceTime call',
      _ => 'activity 0x${action.toRadixString(16).toUpperCase()}',
    };
    final extras = [
      if (flagsHi & 0x1 != 0) 'primary iCloud device',
      if (flagsHi & 0x4 != 0) 'AirDrop receiving on',
      if (dataFlags & 0x04 != 0) 'Wi-Fi on',
      if (dataFlags & 0x01 != 0) 'AirPods connected',
      if (dataFlags & 0x20 != 0) 'Watch locked',
    ];
    final b = StringBuffer(activity[0].toUpperCase() + activity.substring(1));
    if (extras.isNotEmpty) b.write('. ${extras.join('; ')}');
    b.write('.');
    return [AdvField('What the Apple device is doing', b.toString())];
  }

  static String _nearbyInfoReason(Uint8List data) {
    if (data.isEmpty) return 'Nearby Info advertisement.';
    return switch (data[0] & 0x0F) {
      0x03 => 'Phone is idle / locked.',
      0x05 => 'Audio playing with the screen locked.',
      0x07 => 'Screen is on — someone is using it.',
      0x0D => 'Device reports the user is driving.',
      0x0E => 'In a phone or FaceTime call.',
      _ => 'Nearby Info advertisement.',
    };
  }

  static List<AdvField> _decodeFindMy(Uint8List data) {
    if (data.isEmpty) return const [AdvField('Find My', 'Offline Finding advertisement.')];
    final status = data[0];
    final maintained = status & 0x04 != 0;
    final battName = const ['full', 'medium', 'low', 'critical'][(status >> 6) & 0x3];
    final b = StringBuffer()
      ..write('Broadcasting a public key so the Find My network can report a location. ')
      ..write('Used by AirTags, Find My accessories, and Apple devices locating themselves. ')
      ..write(maintained ? 'Owner seen recently. ' : 'Owner not seen in the current key window. ')
      ..write('Battery $battName. ')
      ..write('(${data.length - 1}-byte key fragment — not a serial number.)');
    return [AdvField('Find My / Offline Finding', b.toString())];
  }

  static List<AdvField> _decodeFastPair(Uint8List bytes) {
    if (bytes.length == 3) {
      final id = _modelId24(bytes);
      final m = FastPairModels.models[id];
      return [
        const AdvField('Google Fast Pair', 'In pairing mode — Android will pop a tap-to-pair card.'),
        if (m == null) AdvField('Model ID', '0x${_hex(id, 6)} (not in the local name list)'),
        if (m != null) ...[
          AdvField('Model', m.name),
          if (m.maker.isNotEmpty) AdvField('Maker', m.maker),
          AdvField('Model ID', '0x${_hex(id, 6)}'),
          if (m.tracking) const AdvField('Tracking', 'This model is listed as supporting location tracking.'),
        ],
      ];
    }
    if (bytes.isEmpty) return const [];
    final version = (bytes[0] >> 4) & 0x0F;
    final String ui;
    if (bytes.length > 1) {
      final type = bytes[1] & 0x0F;
      ui = switch (type) {
        0x0 => 'wants to show a pairing card',
        0x2 => 'hiding the pairing card (e.g. buds back in the case)',
        _ => 'filter type $type',
      };
    } else {
      ui = 'account-key bloom filter';
    }
    return [AdvField('Google Fast Pair', 'Already paired to an account (not in pairing mode). $ui. Version $version.')];
  }

  static List<AdvField> _decodeEddystone(Uint8List bytes) {
    if (bytes.isEmpty) return const [];
    final frame = bytes[0];
    switch (frame) {
      case 0x00:
        if (bytes.length < 18) return const [AdvField('Eddystone-UID', 'truncated')];
        return [
          AdvField('Eddystone-UID namespace', _hexUpper(Uint8List.sublistView(bytes, 2, 12))),
          AdvField('Eddystone-UID instance', _hexUpper(Uint8List.sublistView(bytes, 12, 18))),
        ];
      case 0x10:
        return [AdvField('Eddystone-URL', _eddystoneUrl(bytes) ?? '${bytes.length} bytes')];
      case 0x20:
        return const [AdvField('Eddystone-TLM', 'telemetry (battery / temperature / advert count)')];
      case 0x30:
        return const [AdvField('Eddystone-EID', 'ephemeral ID (rotating)')];
      case 0x40:
      case 0x41:
        final mode = frame == 0x41 ? 'separated (unwanted-tracking mode)' : 'nearby / with owner';
        final eidLen = bytes.length >= 33
            ? 32
            : bytes.length >= 21
            ? 20
            : bytes.length - 1;
        final eid = eidLen > 0 ? _hexUpper(Uint8List.sublistView(bytes, 1, 1 + eidLen)) : '';
        return [AdvField('Find Hub', mode), AdvField('Find Hub EID', eid.isEmpty ? '${bytes.length} bytes' : eid)];
      default:
        return [AdvField('Eddystone', 'frame 0x${_hex(frame, 2)}')];
    }
  }

  static String? _eddystoneUrl(Uint8List bytes) {
    if (bytes.length < 3) return null;
    final scheme = switch (bytes[2]) {
      0 => 'http://www.',
      1 => 'https://www.',
      2 => 'http://',
      3 => 'https://',
      _ => null,
    };
    if (scheme == null) return null;
    const expansions = [
      '.com/',
      '.org/',
      '.edu/',
      '.net/',
      '.info/',
      '.biz/',
      '.gov/',
      '.com',
      '.org',
      '.edu',
      '.net',
      '.info',
      '.biz',
      '.gov',
    ];
    final sb = StringBuffer(scheme);
    for (var i = 3; i < bytes.length; i++) {
      final b = bytes[i];
      if (b < expansions.length) {
        sb.write(expansions[b]);
      } else if (b >= 0x20 && b <= 0x7E) {
        sb.writeCharCode(b);
      }
    }
    return sb.toString();
  }

  static List<AdvField> _decodeMicrosoft(Uint8List bytes) {
    if (bytes.isEmpty) return const [];
    if (bytes[0] == 0x01 && bytes.length >= 2) {
      final type = bytes[1] & 0x1F;
      final kind = switch (type) {
        1 => 'Xbox',
        6 => 'iPhone',
        7 => 'iPad',
        8 => 'Android',
        9 => 'Windows desktop',
        11 => 'Windows phone',
        12 => 'Linux',
        13 => 'Windows IoT',
        14 => 'Surface Hub',
        15 => 'Windows laptop',
        16 => 'Windows tablet',
        _ => 'type $type',
      };
      return [
        AdvField('Microsoft Nearby Sharing / Swift Pair', 'A $kind is advertising for quick pairing or sharing.'),
      ];
    }
    return [AdvField('Microsoft manufacturer data', '${bytes.length} bytes')];
  }

  static List<AdvField> _decodeAltBeacon(Uint8List bytes) {
    if (bytes.length >= 22 && bytes[0] == 0xBE && bytes[1] == 0xAC) {
      return [
        AdvField('AltBeacon UUID', _uuidFromBe(bytes, 2)),
        AdvField('AltBeacon major / minor', '${_u16be(bytes, 18)} / ${_u16be(bytes, 20)}'),
      ];
    }
    return const [];
  }

  static int _modelId24(Uint8List b) => (b[0] << 16) | (b[1] << 8) | b[2];

  static int _u16be(Uint8List d, int o) => (d[o] << 8) | d[o + 1];

  static String _hex(int v, int width) => v.toRadixString(16).toUpperCase().padLeft(width, '0');

  static String _hexUpper(Uint8List d) => d.map((b) => _hex(b, 2)).join();

  static String _uuidFromBe(Uint8List d, int o) {
    String h(int i) => d[o + i].toRadixString(16).padLeft(2, '0');
    final s = List.generate(16, h);
    return '${s.sublist(0, 4).join()}-${s.sublist(4, 6).join()}-${s.sublist(6, 8).join()}-'
        '${s.sublist(8, 10).join()}-${s.sublist(10, 16).join()}';
  }
}

Uint8List? hexToBytes(String hex) {
  final h = hexOnly(hex);
  if (h.isEmpty || h.length.isOdd) return null;
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final v = int.tryParse(h.substring(i * 2, i * 2 + 2), radix: 16);
    if (v == null) return null;
    out[i] = v;
  }
  return out;
}
