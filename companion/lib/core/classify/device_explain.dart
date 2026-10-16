import 'adv_decoder.dart';
import 'ble_class.dart';
import 'bt_sig_registry.dart';
import 'vendor_class.dart';
import 'observation.dart';

enum Confidence { high, medium, low }

class Guess {
  final String headline;
  final String because;
  final Confidence confidence;
  final String bucket;
  const Guess(this.headline, this.because, this.confidence, {this.bucket = ''});
}

class _Hint {
  final String bucket;
  final String label;
  final String reason;
  final int weight;
  const _Hint(this.bucket, this.label, this.reason, this.weight);
}

class _SigRule {
  final bool Function(String n) test;
  final String bucket;
  final String label;
  final int weight;
  const _SigRule(this.test, this.bucket, this.label, this.weight);
}

_SigRule _eq(String name, String bucket, String label, int w) => _SigRule((n) => n == name, bucket, label, w);
_SigRule _any(List<String> subs, String bucket, String label, int w) =>
    _SigRule((n) => subs.any(n.contains), bucket, label, w);

final List<_SigRule> _sigRules = [
  _SigRule((n) => n.contains('airtag') || n == 'find my' || n.contains('find hub') || n.contains('dult'), 'tag', '', 8),
  _any(['apple device'], 'phone', 'an iPhone, iPad, or Mac', 7),
  _any(['apple audio'], 'audio-personal', 'AirPods, Beats, or AirPlay', 7),
  _any(['microsoft'], 'computer', 'a Windows / Surface / Xbox radio', 6),
  _eq('tesla tstpms', 'vehicle', 'a Tesla BLE tire sensor', 7),
  _SigRule((n) => n.contains('tpms') || n == 'tirecheck' || n == 'sytpms', 'vehicle', 'a BLE tire-pressure sensor', 7),
  _eq('vuzix', 'glasses', 'Vuzix smart glasses', 7),
  _eq('tesla', 'vehicle', 'a Tesla vehicle (including Cybertruck) or phone-as-key', 7),
  _eq('google', 'phone', 'a Pixel or other Google radio', 6),
  _eq('sony', 'audio-personal', 'Sony headphones, a TV, or a camera', 6),
  _eq('bose', 'audio-personal', 'Bose headphones or a speaker', 7),
  _eq('garmin', 'watch', 'a Garmin watch or inReach', 7),
  _eq('amazon', 'speaker', 'an Echo, Fire, or other Amazon radio', 6),
  _eq('fitbit', 'watch', 'a Fitbit', 7),
  _eq('oura', 'wearable', 'an Oura ring', 7),
  _eq('logitech', 'hid', 'a Logitech mouse, keyboard, or webcam', 6),
  _SigRule((n) => n.contains('jbl') || n == 'harman', 'audio-personal', 'JBL or Harman audio', 6),
  _eq('sonos', 'audio-speaker', 'a Sonos speaker', 7),
  _eq('gopro', 'camera', 'a GoPro', 7),
  _eq('osmo', 'camera', 'a DJI Osmo action camera', 7),
  _eq('insta360', 'camera', 'an Insta360 camera', 7),
  _eq('dji power', 'iot', 'a DJI Power station', 7),
  _eq('dji', 'drone', 'a DJI drone or controller', 7),
  _eq('remote id', 'drone', 'a drone broadcasting ASTM Remote ID', 8),
  _eq('skydio', 'drone', 'a Skydio drone', 7),
  _eq('autel', 'drone', 'an Autel drone', 7),
  _eq('parrot', 'drone', 'a Parrot ANAFI or Bebop drone', 7),
  _eq('hoverair', 'drone', 'a HOVERAir flying camera', 7),
  _SigRule((n) => n == 'netgear' || n == 'orbi', 'ap', 'a NETGEAR or Orbi access point', 6),
  _eq('tp-link', 'ap', 'a TP-Link access point', 6),
  _eq('asus', 'ap', 'an ASUS access point', 6),
  _eq('linksys', 'ap', 'a Linksys or Velop access point', 6),
  _eq('eero', 'ap', 'an Eero mesh node', 6),
  _eq('google wifi', 'ap', 'a Google Wifi or Nest Wifi point', 6),
  _eq('d-link', 'ap', 'a D-Link access point', 6),
  _eq('belkin', 'ap', 'a Belkin access point', 6),
  _eq('xfinity', 'ap', 'an Xfinity gateway or hotspot', 6),
  _eq('spectrum', 'ap', 'a Spectrum gateway or Spectrum Mobile hotspot', 6),
  _eq('at&t', 'ap', 'an AT&T gateway or attwifi hotspot', 6),
  _eq('verizon', 'ap', 'a Verizon or Fios gateway', 6),
  _eq('starlink', 'ap', 'a Starlink router', 7),
  _eq('meraki', 'ap', 'a Cisco Meraki access point', 7),
  _eq('cisco', 'ap', 'a Cisco Aironet, Catalyst, Business, RV, or SPVTG access point', 7),
  _eq('mist', 'ap', 'a Juniper Mist access point', 7),
  _eq('t-mobile', 'ap', 'a T-Mobile Home Internet gateway or hotspot', 6),
  _eq('humax', 'ap', 'a HUMAX gateway (often T-Mobile Home Internet)', 6),
  _eq('sagemcom', 'ap', 'a Sagemcom ISP gateway', 6),
  _eq('arcadyan', 'ap', 'an Arcadyan ISP gateway', 6),
  _eq('askey', 'ap', 'an Askey ISP / 5G gateway', 6),
  _eq('calix', 'ap', 'a Calix fiber gateway', 6),
  _eq('nokia', 'ap', 'a Nokia Solutions and Networks gateway', 6),
  _eq('airties', 'ap', 'an AirTies ISP mesh node', 6),
  _eq('tenda', 'ap', 'a Tenda access point', 6),
  _eq('ruijie', 'ap', 'a Ruijie or Reyee access point', 6),
  _eq('dwnet', 'ap', 'a DWnet access point', 6),
  _eq('wavlink', 'ap', 'a WAVLINK access point', 6),
  _eq('sercomm', 'ap', 'a Sercomm ISP gateway', 6),
  _eq('luxul', 'ap', 'a Luxul access point', 6),
  _eq('sophos', 'ap', 'a Sophos firewall or access point', 7),
  _eq('aumovio', 'hotspot', 'an AUMOVIO / Continental vehicle Wi-Fi radio', 6),
  _eq('centurylink', 'ap', 'a CenturyLink gateway', 6),
  _eq('gm hotspot', 'hotspot', 'a GM in-car hotspot (Cadillac / GMC / Buick / Chevrolet)', 6),
  _eq('audi mmi', 'hotspot', 'an Audi MMI in-car hotspot', 6),
  _eq('extreme', 'ap', 'an Extreme Networks access point', 7),
  _eq('adtran', 'ap', 'an Adtran fiber gateway (often CenturyLink / Quantum Fiber OEM)', 6),
  _eq('cambium', 'ap', 'a Cambium or IgniteNet access point', 6),
  _eq('trendnet', 'ap', 'a TRENDnet access point', 6),
  _eq('cudy', 'ap', 'a Cudy travel or home router', 6),
  _eq('snapav', 'ap', 'a SnapAV / Control4 / Wattbox access point', 6),
  _eq('arlo', 'camera', 'an Arlo camera or VMB base station', 6),
  _eq('vantiva', 'ap', 'a Vantiva or Technicolor ISP gateway', 6),
  _eq('hitron', 'ap', 'a Hitron cable gateway (often Xfinity OEM)', 6),
  _eq('actiontec', 'ap', 'an Actiontec FiOS or Frontier gateway', 6),
  _eq('buffalo', 'ap', 'a Buffalo AirStation or router', 6),
  _eq('grandstream', 'ap', 'a Grandstream GWN access point', 6),
  _eq('edgecore', 'ap', 'an Edgecore access point', 7),
  _eq('watchguard ap', 'ap', 'a WatchGuard firewall or access point', 7),
  _eq('mojo', 'ap', 'a Mojo Networks / Arista Cognitive Wi-Fi access point', 7),
  _eq('winegard', 'hotspot', 'a Winegard RV or marine Wi-Fi radio', 6),
  _eq('inseego', 'ap', 'an Inseego 5G or MiFi hotspot', 6),
  _eq('franklin', 'ap', 'a Franklin Technology 5G home-internet gateway (RG3100 class)', 6),
  _eq('synology', 'ap', 'a Synology NAS or router access point', 6),
  _eq('aruba', 'ap', 'an HPE Aruba Instant or Instant On access point', 7),
  _eq('ruckus', 'ap', 'a RUCKUS access point', 7),
  _eq('fortinet', 'ap', 'a Fortinet FortiAP or FortiWiFi', 7),
  _eq('mikrotik', 'ap', 'a MikroTik router or access point', 6),
  _eq('engenius', 'ap', 'an EnGenius access point', 6),
  _eq('zyxel', 'ap', 'a Zyxel gateway or access point', 6),
  _eq('peplink', 'ap', 'a Peplink or Pepwave router', 6),
  _eq('openwrt', 'ap', 'an OpenWrt router', 6),
  _eq('arris', 'ap', 'an Arris or SURFboard cable gateway', 6),
  _eq('unifi ap', 'ap', 'a Ubiquiti UniFi access point', 7),
  _eq('unifi protect', 'camera', 'a UniFi Protect Instant camera', 7),
  _eq('unifi', 'ap', 'a UniFi / Ubiquiti name', 5),
  _eq('ecobee', 'thermostat', 'an ecobee thermostat', 7),
  _eq('sensi', 'thermostat', 'a Sensi thermostat', 6),
  _eq('honeywell home', 'thermostat', 'a Honeywell Home or Lyric thermostat', 6),
  _any(['honeywell xenon'], 'health', 'a Honeywell Xenon healthcare barcode scanner', 7),
  _eq('omron', 'health', 'an Omron blood-pressure cuff or scale', 7),
  _eq('withings', 'health', 'a Withings scale or blood-pressure monitor', 7),
  _eq('dexcom', 'health', 'a Dexcom glucose sensor', 7),
  _eq('nest thermostat', 'thermostat', 'a Nest thermostat or Nest Labs BLE sensor', 6),
  _eq('nest weave', 'sensor', 'a Nest Protect, camera, or other Weave BLE device', 7),
  _SigRule((n) => n == 'haiku fan' || n == 'haiku', 'fan', 'a Haiku or Mammoth ceiling fan', 7),
  _eq('tuya', 'iot', 'a Tuya BLE gadget (plug, light, camera, sensor)', 6),
  _SigRule(
    (n) => n == 'seos' || n == 'assa abloy',
    'access',
    'an ASSA ABLOY lock, Yale lock, HID reader, or Seos credential',
    7,
  ),
  _eq('august', 'lock', 'an August smart lock', 7),
  _eq('schlage', 'lock', 'a Schlage or Allegion lock', 7),
  _eq('nuki', 'lock', 'a Nuki lock or opener', 7),
  _eq('salto', 'access', 'a SALTO access reader or lock', 7),
  _eq('dormakaba', 'access', 'a dormakaba, Saflok, or Oracode lock', 7),
  _eq('lockly', 'lock', 'a Lockly smart lock', 6),
  _eq('kevo', 'lock', 'a Kwikset Kevo or Unikey lock', 7),
  _eq('master lock', 'lock', 'a Master Lock padlock', 7),
  _eq('igloohome', 'lock', 'an igloohome lock or keybox', 7),
  _eq('tedee', 'lock', 'a Tedee smart lock', 7),
  _eq('paxton', 'access', 'a Paxton reader or Net2 access point', 7),
  _eq('kwikset', 'lock', 'a Kwikset lock', 6),
  _eq('myq', 'garage', 'a Chamberlain myQ garage hub', 7),
  _eq('chevrolet hotspot', 'hotspot', 'a Chevrolet in-car Wi-Fi hotspot', 7),
  _eq('rivian', 'vehicle', 'a Rivian vehicle, phone key, or sensor', 7),
  _eq('ford', 'vehicle', 'a Ford or Lincoln vehicle or phone-as-key', 7),
  _eq('honda', 'vehicle', 'a Honda or Acura vehicle or phone-as-key', 7),
  _eq('hyundai', 'vehicle', 'a Hyundai or Genesis vehicle or phone-as-key', 7),
  _eq('toyota', 'vehicle', 'a Toyota or Lexus vehicle or phone-as-key', 7),
  _eq('nissan', 'vehicle', 'a Nissan or Infiniti vehicle or phone-as-key', 7),
  _eq('subaru', 'vehicle', 'a Subaru vehicle or phone-as-key', 7),
  _eq('bmw', 'vehicle', 'a BMW vehicle, phone-as-key, or factory hotspot', 7),
  _eq('volkswagen', 'vehicle', 'a Volkswagen vehicle or phone-as-key', 7),
  _eq('porsche', 'vehicle', 'a Porsche vehicle or phone-as-key', 7),
  _eq('jaguar land rover', 'vehicle', 'a Jaguar, Land Rover, or Range Rover', 7),
  _eq('byd', 'vehicle', 'a BYD vehicle or phone-as-key', 7),
  _eq('govee', 'light', 'a Govee light or sensor', 6),
  _eq('hp', 'printer', 'an HP printer', 6),
  _eq('epson', 'printer', 'an Epson EcoTank or WorkForce printer', 6),
  _eq('lg webos tv', 'tv', 'an LG webOS TV', 7),
  _eq('roku', 'tv', 'a Roku streaming stick or Roku TV (often a hidden Wi-Fi Direct remote AP)', 7),
  _eq('samsung appliance', 'iot', 'a Samsung fridge, range, oven, or cooktop (setup AP)', 6),
  _eq('ecowater', 'iot', 'an EcoWater water softener (setup AP)', 6),
  _eq('nespresso', 'iot', 'a Nespresso coffee machine', 7),
  _eq('radiacode', 'sensor', 'a RadiaCode radiation detector', 7),
  _eq('shokz', 'audio-personal', 'Shokz OpenRun or OpenFit headphones', 7),
  _eq('mercedes mbux', 'hotspot', 'a Mercedes MBUX in-car hotspot', 7),
  _eq('motive', 'hotspot', 'a Motive / KeepTruckin fleet ELD hotspot', 6),
  _eq('peoplenet', 'hotspot', 'a PeopleNet fleet ELD hotspot', 6),
  _eq('uconnect', 'hotspot', 'a Uconnect in-car hotspot', 6),
  _eq('carplay', 'hotspot', 'a CarPlay in-car hotspot', 6),
  _eq('cradlepoint', 'hotspot', 'a Cradlepoint vehicle router (often public-safety / fleet)', 7),
  _eq('airlink', 'hotspot', 'a Sierra Wireless AirLink vehicle gateway', 7),
  _eq('compex', 'hotspot', 'a Compex access point (sometimes public-safety / fleet)', 6),
  _eq('novatel wireless', 'hotspot', 'a Novatel Wireless / Inseego vehicle radio', 6),
  _eq('utility inc', 'hotspot', 'a Utility, Inc vehicle or public-safety radio', 6),
  _SigRule((n) => n.contains('gl.inet') || n == 'glinet', 'ap', 'a GL.iNet travel router', 6),
  _any(['smarttag'], 'tag', 'a Samsung SmartTag', 8),
  _any(['tile'], 'tag', 'a Tile tracker', 8),
  _eq('ibeacon', 'beacon', 'an iBeacon', 7),
  _any(['atrius'], 'beacon', 'an Atrius cart tag', 8),
  _eq('minew', 'beacon', 'a Minew BLE beacon or sensor', 7),
  _eq('estimote', 'beacon', 'an Estimote beacon', 7),
  _SigRule((n) => n == 'kontakt.io' || n == 'kontakt', 'beacon', 'a Kontakt.io beacon', 7),
  _any(['bluetoad'], 'roadside', 'an Iteris BlueTOAD / Vantage Velocity roadside Bluetooth travel-time reader', 7),
  _any(['bliptrack'], 'roadside', 'a BLIP Systems BlipTrack roadside travel-time sensor', 7),
  _any(
    ['raven', 'shotspotter', 'soundthinking'],
    'acoustic',
    'a Flock Raven or ShotSpotter acoustic gunshot sensor',
    8,
  ),
  _any(['digital ally'], 'camera', 'a Digital Ally body-worn or in-car camera', 8),
  _any(['reveal media', 'bodyworn'], 'camera', 'a Reveal Media body-worn camera', 8),
  _eq('wolfcom', 'camera', 'a Wolfcom body-worn or in-car camera', 8),
  _any(['i-pro', 'arbitrator'], 'camera', 'a Panasonic i-PRO camera or Arbitrator in-car system', 8),
  _any(['limitless'], 'wearable', 'a Limitless Pendant conversation recorder', 8),
  _SigRule((n) => n == 'bee pendant' || n.contains('bee pioneer'), 'wearable', 'a Bee Pioneer wearable recorder', 8),
  _SigRule((n) => n == 'omi' || n.contains('openglass'), 'wearable', 'an Omi pendant or OpenGlass camera glasses', 8),
  _any(['friend pendant'], 'wearable', 'a Friend Pendant necklace', 8),
  _any(['brilliant frame'], 'glasses', 'Brilliant Labs Frame AR glasses', 8),
  _eq('even g1', 'glasses', 'Even Realities G1 glasses', 8),
  _any(['hayden'], 'camera', 'a Hayden AI bus- or vehicle-mounted camera', 8),
  _any(['miovision'], 'camera', 'a Miovision intersection traffic camera', 8),
  _eq('tattile', 'camera', 'a Tattile plate reader', 8),
  _any(['lvt', 'liveview'], 'camera', 'an LVT / LiveView solar surveillance trailer', 8),
  _any(['hanwha', 'wisenet'], 'camera', 'a Hanwha Vision / Wisenet camera', 7),
  _eq('uniview', 'camera', 'a Uniview / UNV camera', 7),
  _eq('rhombus', 'camera', 'a Rhombus cloud camera', 7),
  _eq('meshcore', 'mesh', 'a MeshCore LoRa companion radio', 7),
  _any(['gotenna'], 'mesh', 'a goTenna Mesh or Pro radio', 7),
  _eq('sensecap', 'mesh', 'a SenseCAP LoRaWAN / Helium gateway', 7),
  _SigRule((n) => n.contains('wisgate') || n == 'rak wisgate', 'mesh', 'a RAK WisGate LoRaWAN gateway', 7),
  _eq('ghostesp', 'pentest', 'a GhostESP ESP32 audit board', 7),
  _eq('bruce', 'pentest', 'a Bruce ESP32 pentest board', 7),
  _eq('liteon camera radio', 'module', 'a camera-module radio (LiteOn or similar)', 3),
  _any(['chipolo', 'pebblebee', 'moto tag'], 'tag', 'a finder tag', 7),
  _any(['airpods'], 'audio-personal', 'AirPods', 8),
];

class DeviceExplain {
  static Guess guess(
    Observation device,
    List<String> signatureNames, {
    String? vendor,
    String? baseVendor,
  }) {
    final vh = VendorClass.hint(device, vendor, baseVendor: baseVendor);
    final apVendor = vh != null && vh.weight >= 3 && device.kind == RadioKind.wifi && device.isAp;
    final hints = <_Hint>[
      if (vh != null) _Hint(vh.bucket, vh.label, vh.reason, vh.weight),
      ..._uuidHints([...device.serviceUuids, ...device.serviceData.map((s) => s.uuid)]),
      for (final h in AdvPayloadDecoder.roleHints(device)) _Hint(h.bucket, h.label, h.reason, h.weight),
      for (final h in BleClass.hints(device)) _Hint(h.bucket, h.label, h.reason, h.weight),
      for (final h in BtSigRegistry.hints(device)) _Hint(h.bucket, h.label, h.reason, h.weight),
      ..._signatureHints(signatureNames),
      if (device.kind == RadioKind.wifi) ..._wifiHints(device, signatureNames, hasVendor: apVendor),
    ];
    if (hints.isEmpty) {
      return Guess(
        device.kind == RadioKind.wifi ? 'Wi-Fi access point' : 'Bluetooth LE advertiser',
        'It is on the air, but it did not advertise a product class '
        '(no Appearance, Class of Device, or well-known service that names a type).',
        Confidence.low,
      );
    }
    final sorted = [...hints]..sort((a, b) => b.weight.compareTo(a.weight));
    final grouped = <String, _Hint>{};
    for (final h in sorted) {
      final prev = grouped[h.bucket];
      if (prev == null || h.weight > prev.weight) grouped[h.bucket] = h;
    }
    final best = grouped.values.reduce((a, b) => b.weight > a.weight ? b : a);
    final support = grouped.values
        .where((h) => h.bucket == best.bucket || h.weight >= 3)
        .map((h) => h.reason)
        .toSet()
        .toList();
    final confidence = best.weight >= 6
        ? Confidence.high
        : best.weight >= 3
        ? Confidence.medium
        : Confidence.low;
    final hedge = switch (confidence) {
      Confidence.high => 'Most likely',
      Confidence.medium => 'Probably',
      Confidence.low => 'Could be',
    };
    return Guess(
      '$hedge ${best.label}',
      support.join(' '),
      confidence,
      bucket: best.bucket,
    );
  }

  static bool isGeneric(Guess g) {
    final h = g.headline.toLowerCase();
    return h.contains('bluetooth le advertiser') || h.endsWith('a wi-fi access point');
  }

  static String stripHedge(String headline) => headline.replaceFirst(RegExp(r'^(Most likely|Probably|Could be) '), '');

  static String hedge(Confidence c) => switch (c) {
    Confidence.high => 'Most likely',
    Confidence.medium => 'Probably',
    Confidence.low => 'Could be',
  };

  static String? listLabel(Observation device, {List<String> signatureNames = const [], String? vendor, Guess? guessed}) {
    final g = guessed ?? guess(device, signatureNames, vendor: vendor);
    final h = g.headline.toLowerCase();
    final generic = h.contains('bluetooth le advertiser') || h.contains('wi-fi access point');
    final core = generic ? null : _tidyHeadline(g.headline);
    final v = vendor?.trim();
    final vend = (v != null && v.isNotEmpty && v.length <= 24) ? v : null;
    if (core != null) {
      return vend != null && !core.toLowerCase().contains(vend.toLowerCase()) ? '$vend · $core' : core;
    }
    return vend != null ? '$vend device' : null;
  }

  static String _tidyHeadline(String headline) {
    var s = headline;
    for (final p in ['Most likely ', 'Probably ', 'Could be ']) {
      if (s.startsWith(p)) s = s.substring(p.length);
    }
    s = s.trim().replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    for (final p in ['an ', 'a ']) {
      if (s.startsWith(p)) s = s.substring(p.length);
    }
    s = s.trim();
    if (s.isEmpty) return headline;
    return s[0].toUpperCase() + s.substring(1);
  }

  static String flagsExplain(int flags) => [
    if (flags & 0x01 != 0) 'Pairing now' else if (flags & 0x02 != 0) 'Discoverable',
    if (flags & 0x04 != 0) 'Bluetooth LE only' else 'Bluetooth LE + Classic',
  ].join(' · ');

  static String addressExplain(Observation device, {String? addressType}) {
    final local = (int.tryParse(MacUtil.normalize(device.mac).split(':').first, radix: 16) ?? 0) & 0x02 != 0;
    final type = addressType?.toLowerCase();
    if (device.kind == RadioKind.wifi && device.randomized) return 'Custom · fixed';
    if (local && !device.randomized) return 'Custom · fixed';
    if (type == 'public' && !device.randomized) return 'Factory · fixed';
    if (type == 'random' || device.randomized) return 'Random · changes over time';
    if (type == 'anonymous') return 'Hidden';
    return 'Factory · fixed';
  }

  static bool rssiMeasured(int rssi) => rssi >= -127 && rssi <= 126;

  static String rssiBand(int rssi) {
    if (!rssiMeasured(rssi)) return 'not available';
    if (rssi >= -45) return 'very strong';
    if (rssi >= -60) return 'strong';
    if (rssi >= -75) return 'medium';
    if (rssi >= -88) return 'weak';
    return 'very weak';
  }

  static String rssiExplain(int rssi) => rssiMeasured(rssi) ? '$rssi dBm · ${rssiBand(rssi)}' : 'Not available';

  static String? uuidGloss(String uuid) => switch (_uuid16(uuid)) {
    0x1800 => 'connection basics',
    0x1801 => 'attribute protocol',
    0x180A => 'model / serial / firmware',
    0x180F => 'battery level',
    0x1812 => 'keyboard, mouse, or gamepad',
    0x180D => 'heart-rate sensor',
    0x1810 => 'blood-pressure sensor',
    0x181A => 'temperature / humidity style sensor',
    0x1844 || 0x1845 || 0x1846 => 'LE cycling power/speed',
    0x1850 || 0x184E || 0x184F => 'LE Audio',
    0xFE2C => 'Google Fast Pair (often buds/speakers)',
    0xFD5A => 'Samsung SmartTag',
    0xFD44 => 'Apple Find My related',
    0xFEED || 0xFEDD => 'Tile tracker',
    0xFD50 => 'Tuya IoT',
    0xFEBE || 0xFE21 => 'Bose',
    0xFE78 => 'HP printer',
    0xFE07 => 'Sonos speaker',
    0xFEAF || 0xFEB0 => 'Nest Weave',
    0xFCBF => 'ASSA ABLOY Opening Solutions',
    0xFE24 => 'August Home lock',
    0xFCF4 => 'Allegion / Schlage',
    0xFCB2 => 'Apple (not ASSA ABLOY)',
    _ => null,
  };

  static List<_Hint> _uuidHints(List<String> uuids) {
    final out = <_Hint>[];
    for (final u in uuids) {
      final h = switch (_uuid16(u)) {
        0x1812 => const _Hint(
          'hid',
          'a keyboard, mouse, or gamepad',
          'It offers the Bluetooth service keyboards, mice and controllers use.',
          5,
        ),
        0x1108 || 0x1112 || 0x111E || 0x110B || 0x110A || 0x1131 || 0x1203 => const _Hint(
          'audio-personal',
          'headphones, a headset, or a speaker',
          'It offers Bluetooth audio, like headphones and speakers.',
          5,
        ),
        0x184E || 0x184F || 0x1850 || 0x1851 => const _Hint(
          'audio-personal',
          'LE Audio earbuds or a speaker',
          'It offers newer Bluetooth LE Audio, used by recent earbuds and speakers.',
          6,
        ),
        0x180D => const _Hint('health', 'a heart-rate monitor', 'It shares heart-rate readings over Bluetooth.', 6),
        0x1810 => const _Hint('health', 'a blood-pressure monitor', 'It shares blood-pressure readings over Bluetooth.', 6),
        0x181A => const _Hint('sensor', 'an environmental sensor', 'It shares temperature or other environment readings over Bluetooth.', 4),
        0xFE2C => const _Hint(
          'audio-personal',
          'earbuds or a speaker',
          'It sends a Google Fast Pair signal, used by earbuds and speakers.',
          4,
        ),
        0xFD5A => const _Hint('tag', 'a Samsung SmartTag', 'It sends the Bluetooth signal Samsung SmartTags use.', 7),
        0xFD44 => const _Hint('tag', 'an Apple Find My accessory', 'It sends a signal used by Apple Find My accessories.', 6),
        0xFEED || 0xFEDD => const _Hint('tag', 'a Tile tracker', 'It sends the Bluetooth signal Tile trackers use.', 7),
        _ => null,
      };
      if (h != null) out.add(h);
    }
    return out;
  }

  static bool _isGeneric(String name) {
    final n = name.trim().toLowerCase();
    return n == 'unknown signature' || n == 'unknown fleet';
  }

  static List<_Hint> _signatureHints(List<String> names) {
    final out = <_Hint>[];
    for (final raw in names) {
      if (_isGeneric(raw)) continue;
      final n = raw.toLowerCase();
      final reason = 'Matched signature $raw.';
      final rule = _sigRules.where((r) => r.test(n)).firstOrNull;
      if (rule == null) {
        out.add(_Hint('named', raw, reason, 7));
      } else if (identical(rule, _sigRules.first)) {
        final label = n.contains('dult')
            ? 'a DULT finder tag'
            : n.contains('find hub')
            ? 'a Google Find Hub tag'
            : 'an Apple AirTag / Find My tag';
        out.add(_Hint(rule.bucket, label, reason, rule.weight));
      } else {
        out.add(_Hint(rule.bucket, rule.label, reason, rule.weight));
      }
    }
    return out;
  }

  static List<_Hint> _wifiHints(Observation device, List<String> signatureNames, {bool hasVendor = false}) {
    final name = device.name.toLowerCase();
    final specific = signatureNames.any((n) => !_isGeneric(n));
    if (name.startsWith('direct-')) {
      return [
        specific
            ? const _Hint('wifi-direct', 'a Wi-Fi Direct access point', 'Its network name starts with "DIRECT-", which Wi-Fi Direct devices use.', 4)
            : const _Hint('wifi-direct', 'a phone or TV using Wi-Fi Direct', 'Its network name starts with "DIRECT-", which Wi-Fi Direct devices use.', 6),
      ];
    }
    if (name.startsWith('android-') || name.contains('hotspot')) {
      return specific ? const [] : const [_Hint('hotspot', 'a phone hotspot', 'Its network name looks like a phone hotspot.', 6)];
    }
    if (device.hiddenSsid) {
      return const [_Hint('ap', 'a hidden Wi-Fi access point', 'It hides its network name but is still broadcasting.', 4)];
    }
    return specific || hasVendor ? const [] : const [_Hint('ap', 'a Wi-Fi access point', 'It is a Wi-Fi network broadcasting its name.', 3)];
  }

  static int? _uuid16(String uuid) {
    final hex = hexOnly(uuid);
    if (hex.length == 8) return int.tryParse(hex.substring(4), radix: 16);
    return uuid16(uuid);
  }
}
