import 'package:oui_spy/core/classify/adv_decoder.dart';
import 'package:oui_spy/core/classify/observation.dart';

class VendorRule {
  final String token;
  final String bucket;
  final String label;
  final int weight;
  const VendorRule(this.token, this.bucket, this.label, this.weight);
}

class VendorClass {
  const VendorClass._();

  static RoleHint? hint(Observation o, String? vendor, {String? baseVendor}) {
    if (o.mac.isEmpty) return null;
    if (vendor != null && !o.randomized) {
      final r = ruleForKind(vendor, o.kind);
      return r == null ? null : RoleHint(r.bucket, r.label, 'Made by $vendor (from its MAC address).', r.weight);
    }
    if (baseVendor != null && o.isAp && o.randomized) {
      final r = ruleForKind(baseVendor, o.kind);
      return r == null
          ? null
          : RoleHint(
              r.bucket,
              r.label,
              'Its network address is a locally-administered variant of a $baseVendor address, '
              'which routers and phones use for extra networks.',
              r.weight,
            );
    }
    return null;
  }

  static VendorRule? ruleForKind(String vendor, RadioKind kind) {
    if (kind == RadioKind.wifi) {
      final v = vendor.toLowerCase();
      for (final r in wifiRules) {
        if (wordMatch(v, r.token)) return r;
      }
    }
    return ruleFor(vendor);
  }

  static const wifiRules = <VendorRule>[
    VendorRule('google', 'ap', 'a Google Wifi / Nest Wifi router or Chromecast setup network', 3),
    VendorRule('motorola mobility', 'hotspot', 'a Motorola phone hotspot', 4),
    VendorRule('apple', 'ap', 'an iPhone / iPad hotspot or Apple AirPort base station', 3),
    VendorRule('hewlett packard enterprise', 'ap', 'an HPE Aruba access point', 4),
    VendorRule('espressif', 'iot', 'an ESP32 / ESP8266 gadget or its setup network', 3),
    VendorRule('texas instruments', 'iot', 'a Wi-Fi IoT device (TI SimpleLink chip)', 3),
    VendorRule('silicon laboratories', 'iot', 'a Wi-Fi IoT device (Silicon Labs chip)', 3),
    VendorRule('nordic semiconductor', 'iot', 'a Wi-Fi IoT device (Nordic chip)', 3),
  ];

  static const tableAssets = [
    'assets/classify/vendor_categories_0.tsv',
    'assets/classify/vendor_categories_1.tsv',
    'assets/classify/vendor_categories_2.tsv',
    'assets/classify/vendor_categories_3.tsv',
    'assets/classify/vendor_categories_4.tsv',
  ];

  static final _table = <String, VendorRule>{};

  static void loadTable(Iterable<String> tsvs) {
    for (final tsv in tsvs) {
      for (final line in tsv.split('\n')) {
        final f = line.trimRight().split('\t');
        if (f.length != 3 || f[1] == 'unknown' || (f[2] != 'h' && f[2] != 'm')) continue;
        final noun = _nouns[f[1]];
        if (noun == null) continue;
        _table[f[0].toLowerCase()] = VendorRule(
          f[2],
          f[1] == 'audio' ? 'audio-personal' : f[1],
          'a ${f[0]} $noun',
          f[2] == 'h' ? 3 : 2,
        );
      }
    }
  }

  static VendorRule? ruleFor(String vendor) {
    final v = vendor.toLowerCase();
    VendorRule? hand;
    for (final r in rules) {
      if (wordMatch(v, r.token)) {
        hand = r;
        break;
      }
    }
    if (hand != null && hand.weight >= 2) return hand;
    return _table[v] ?? hand;
  }

  static const _nouns = {
    'camera': 'camera',
    'bodyworn': 'body-worn camera',
    'law-enforcement': 'law-enforcement device',
    'drone': 'drone',
    'vehicle': 'vehicle device',
    'phone': 'phone',
    'computer': 'computer',
    'tv': 'TV or media player',
    'console': 'game console',
    'audio': 'audio device',
    'wearable': 'wearable',
    'glasses': 'smart glasses',
    'health': 'health or medical device',
    'tag': 'tracker tag',
    'beacon': 'beacon',
    'lock': 'smart lock',
    'home': 'smart-home device or appliance',
    'thermostat': 'thermostat',
    'printer': 'printer',
    'pos': 'payment terminal or barcode scanner',
    'network': 'network device',
    'router': 'router or gateway',
    'isp': 'ISP gateway',
    'iot': 'IoT device',
    'iot-module': 'radio chip, inside another brand\'s product',
    'industrial': 'industrial device',
    'signage': 'signage display',
    'hacking': 'security-testing tool',
  };

  static bool wordMatch(String v, String token) {
    bool alnum(int i) => i >= 0 && i < v.length && RegExp(r'[a-z0-9]').hasMatch(v[i]);
    for (var i = v.indexOf(token); i >= 0; i = v.indexOf(token, i + 1)) {
      if (!alnum(i - 1) && !alnum(i + token.length)) return true;
    }
    return false;
  }

  static const rules = <VendorRule>[
    VendorRule('hikvision', 'camera', 'a Hikvision camera or recorder', 3),
    VendorRule('dahua', 'camera', 'a Dahua camera or recorder', 3),
    VendorRule('axis communications', 'camera', 'an Axis network camera', 3),
    VendorRule('hanwha', 'camera', 'a Hanwha (Wisenet) camera', 3),
    VendorRule('uniview', 'camera', 'a Uniview camera', 3),
    VendorRule('vivotek', 'camera', 'a Vivotek camera', 3),
    VendorRule('mobotix', 'camera', 'a Mobotix camera', 3),
    VendorRule('avigilon', 'camera', 'an Avigilon camera', 3),
    VendorRule('verkada', 'camera', 'a Verkada camera or sensor', 3),
    VendorRule('reolink', 'camera', 'a Reolink camera', 3),
    VendorRule('amcrest', 'camera', 'an Amcrest camera', 3),
    VendorRule('arlo technology', 'camera', 'an Arlo camera', 3),
    VendorRule('wyze', 'camera', 'a Wyze camera or smart-home device', 3),
    VendorRule('ring llc', 'camera', 'a Ring doorbell or camera', 3),
    VendorRule('blink by amazon', 'camera', 'a Blink camera', 3),
    VendorRule('lorex', 'camera', 'a Lorex camera', 3),
    VendorRule('swann', 'camera', 'a Swann camera', 3),
    VendorRule('ezviz', 'camera', 'an EZVIZ camera', 3),
    VendorRule('flir', 'camera', 'a FLIR thermal camera', 3),
    VendorRule('rhombus', 'camera', 'a Rhombus camera', 3),
    VendorRule('gopro', 'camera', 'a GoPro camera', 3),
    VendorRule('axon enterprise', 'radio', 'an Axon body camera or device', 4),
    VendorRule('taser international', 'radio', 'an Axon (TASER) body camera or weapon', 4),
    VendorRule('digi international', 'router', 'a Digi cellular router or module', 2),
    VendorRule('mikrotikls', 'network', 'a MikroTik router', 3),
    VendorRule('dexcom', 'health', 'a Dexcom glucose monitor', 4),
    VendorRule('tile', 'tag', 'a Tile tracker', 4),
    VendorRule('chipolo', 'tag', 'a Chipolo tracker', 4),
    VendorRule('rivian automotive', 'vehicle', 'a Rivian vehicle', 4),
    VendorRule('nissan motor', 'vehicle', 'a Nissan vehicle', 4),
    VendorRule('geotab', 'vehicle', 'a Geotab fleet tracker', 4),
    VendorRule('allterco robotics', 'home', 'a Shelly smart relay', 3),
    VendorRule('motorola solutions', 'radio', 'a Motorola Solutions radio or camera', 3),
    VendorRule('kenwood', 'radio', 'a Kenwood radio', 2),
    VendorRule('icom inc', 'radio', 'an Icom radio', 2),
    VendorRule('sepura', 'radio', 'a Sepura radio', 3),
    VendorRule('cradlepoint', 'router', 'a Cradlepoint cellular router (often in vehicles)', 3),
    VendorRule('sierra wireless', 'router', 'a Sierra Wireless cellular modem', 2),
    VendorRule('inseego', 'router', 'an Inseego hotspot', 3),
    VendorRule('peplink', 'router', 'a Peplink cellular router', 3),
    VendorRule('dji', 'drone', 'a DJI drone or controller', 4),
    VendorRule('parrot sa', 'drone', 'a Parrot drone', 3),
    VendorRule('skydio', 'drone', 'a Skydio drone', 4),
    VendorRule('apple', 'phone', 'an Apple device (iPhone, iPad, Mac, Watch)', 2),
    VendorRule('samsung electronics', 'phone', 'a Samsung phone, TV, or appliance', 1),
    VendorRule('google', 'phone', 'a Google device (Pixel, Nest, Chromecast)', 1),
    VendorRule('xiaomi', 'phone', 'a Xiaomi phone or smart-home device', 1),
    VendorRule('huawei device', 'phone', 'a Huawei phone or wearable', 2),
    VendorRule('honor device', 'phone', 'an Honor phone', 2),
    VendorRule('oppo mobile', 'phone', 'an OPPO phone', 2),
    VendorRule('vivo mobile', 'phone', 'a vivo phone', 2),
    VendorRule('oneplus', 'phone', 'a OnePlus phone', 2),
    VendorRule('realme', 'phone', 'a realme phone', 2),
    VendorRule('motorola mobility', 'phone', 'a Motorola phone', 2),
    VendorRule('lg electronics (mobile communications)', 'phone', 'an LG phone', 2),
    VendorRule('nokia corporation', 'phone', 'a Nokia phone', 1),
    VendorRule('hmd global', 'phone', 'a Nokia (HMD) phone', 2),
    VendorRule('itel mobile', 'phone', 'an itel phone', 2),
    VendorRule('zte corporation', 'phone', 'a ZTE phone or router', 1),
    VendorRule('tcl', 'tv', 'a TCL TV or phone', 1),
    VendorRule('sony interactive', 'console', 'a PlayStation', 3),
    VendorRule('nintendo', 'console', 'a Nintendo console or controller', 3),
    VendorRule('valve corporation', 'console', 'a Steam Deck or Valve device', 2),
    VendorRule('microsoft', 'computer', 'a Microsoft device (Surface, Xbox)', 1),
    VendorRule('dell', 'computer', 'a Dell computer', 2),
    VendorRule('lenovo', 'computer', 'a Lenovo computer', 1),
    VendorRule('hewlett packard enterprise', 'network', 'an HPE/Aruba access point', 2),
    VendorRule('hewlett packard', 'computer', 'an HP computer or printer', 1),
    VendorRule('asustek', 'computer', 'an ASUS computer or router', 1),
    VendorRule('acer', 'computer', 'an Acer computer', 2),
    VendorRule('intel corporate', 'computer', 'a computer with an Intel Wi-Fi card', 1),
    VendorRule('liteon', 'computer', 'a laptop or PC (Lite-On Wi-Fi/Bluetooth card)', 1),
    VendorRule('azurewave', 'computer', 'a laptop or PC (AzureWave Wi-Fi/Bluetooth card)', 2),
    VendorRule('hon hai', 'computer', 'a Foxconn-built device', 1),
    VendorRule('cloud network technology', 'computer', 'a Foxconn-built laptop', 1),
    VendorRule('raspberry pi', 'computer', 'a Raspberry Pi', 3),
    VendorRule('canon', 'printer', 'a Canon printer or camera', 2),
    VendorRule('seiko epson', 'printer', 'an Epson printer', 3),
    VendorRule('brother industries', 'printer', 'a Brother printer', 3),
    VendorRule('xerox corporation', 'printer', 'a Xerox printer', 3),
    VendorRule('kyocera', 'printer', 'a Kyocera printer or phone', 2),
    VendorRule('ricoh', 'printer', 'a Ricoh printer', 3),
    VendorRule('zebra technologies', 'pos', 'a Zebra scanner or label printer', 3),
    VendorRule('honeywell', 'industrial', 'a Honeywell scanner, thermostat, or building device', 1),
    VendorRule('ingenico', 'pos', 'an Ingenico card terminal', 3),
    VendorRule('verifone', 'pos', 'a Verifone card terminal', 3),
    VendorRule('pax computer', 'pos', 'a PAX card terminal', 3),
    VendorRule('toast', 'pos', 'a Toast restaurant terminal', 3),
    VendorRule('meraki', 'network', 'a Cisco Meraki access point', 3),
    VendorRule('linksys', 'network', 'a Linksys router', 3),
    VendorRule('cisco', 'network', 'a Cisco access point or switch', 2),
    VendorRule('juniper networks', 'network', 'a Juniper/Mist access point', 3),
    VendorRule('ruckus', 'network', 'a Ruckus access point', 3),
    VendorRule('extreme networks', 'network', 'an Extreme Networks access point', 3),
    VendorRule('ubiquiti', 'network', 'a Ubiquiti access point or camera', 2),
    VendorRule('fortinet', 'network', 'a Fortinet access point or firewall', 3),
    VendorRule('routerboard', 'network', 'a MikroTik router', 3),
    VendorRule('netgear', 'network', 'a Netgear router', 3),
    VendorRule('tp-link', 'network', 'a TP-Link router, plug, or camera', 2),
    VendorRule('d-link', 'network', 'a D-Link router or camera', 2),
    VendorRule('belkin', 'network', 'a Belkin router or smart plug', 2),
    VendorRule('eero', 'network', 'an eero mesh router', 3),
    VendorRule('zyxel', 'network', 'a Zyxel router', 3),
    VendorRule('arcadyan', 'isp', 'an ISP gateway (Arcadyan)', 3),
    VendorRule('sagemcom', 'isp', 'an ISP gateway (Sagemcom)', 3),
    VendorRule('commscope', 'isp', 'an ISP gateway (CommScope/ARRIS)', 3),
    VendorRule('arris', 'isp', 'an ISP cable modem (ARRIS)', 3),
    VendorRule('technicolor', 'isp', 'an ISP gateway (Technicolor)', 3),
    VendorRule('vantiva', 'isp', 'an ISP gateway (Vantiva)', 3),
    VendorRule('askey', 'isp', 'an ISP gateway (Askey)', 3),
    VendorRule('fiberhome', 'isp', 'an ISP fiber gateway (FiberHome)', 3),
    VendorRule('sercomm', 'isp', 'an ISP gateway or camera (Sercomm)', 2),
    VendorRule('calix', 'isp', 'an ISP fiber gateway (Calix)', 3),
    VendorRule('adtran', 'isp', 'an ISP gateway (Adtran)', 3),
    VendorRule('nokia shanghai bell', 'isp', 'an ISP fiber gateway (Nokia)', 3),
    VendorRule('huawei technologies', 'network', 'a Huawei router or phone', 1),
    VendorRule('h3c', 'network', 'an H3C access point', 3),
    VendorRule('skyworth', 'tv', 'a Skyworth TV or set-top box', 3),
    VendorRule('vizio', 'tv', 'a Vizio TV', 3),
    VendorRule('roku', 'tv', 'a Roku player or TV', 3),
    VendorRule('hisense', 'tv', 'a Hisense TV', 1),
    VendorRule('lg electronics', 'tv', 'an LG TV or appliance', 2),
    VendorRule('panasonic', 'tv', 'a Panasonic device', 1),
    VendorRule('sharp', 'tv', 'a Sharp TV', 2),
    VendorRule('philips', 'home', 'a Philips device', 1),
    VendorRule('amazon technologies', 'home', 'an Amazon Echo, Fire TV, or Ring device', 2),
    VendorRule('sonos', 'audio-personal', 'a Sonos speaker', 3),
    VendorRule('bose', 'audio-personal', 'a Bose speaker or headphones', 3),
    VendorRule('harman', 'audio-personal', 'a Harman/JBL speaker or car audio', 2),
    VendorRule('bang & olufsen', 'audio-personal', 'a Bang & Olufsen speaker', 3),
    VendorRule('sennheiser', 'audio-personal', 'Sennheiser headphones', 3),
    VendorRule('gn audio', 'audio-personal', 'a Jabra headset', 3),
    VendorRule('gn hearing', 'health', 'a ReSound hearing aid', 3),
    VendorRule('skullcandy', 'audio-personal', 'Skullcandy headphones', 3),
    VendorRule('plantronics', 'audio-personal', 'a Poly headset', 3),
    VendorRule('signify', 'home', 'a Philips Hue light', 3),
    VendorRule('ecobee', 'home', 'an ecobee thermostat', 3),
    VendorRule('nest labs', 'home', 'a Nest thermostat or camera', 3),
    VendorRule('irobot', 'home', 'a Roomba', 3),
    VendorRule('roborock', 'home', 'a Roborock robot vacuum', 3),
    VendorRule('dyson', 'home', 'a Dyson appliance', 3),
    VendorRule('tuya', 'home', 'a Tuya smart-home device', 3),
    VendorRule('lutron', 'home', 'a Lutron light control', 3),
    VendorRule('chamberlain', 'home', 'a myQ garage opener', 3),
    VendorRule('simplisafe', 'home', 'a SimpliSafe alarm', 3),
    VendorRule('resideo', 'home', 'a Resideo/Honeywell Home device', 3),
    VendorRule('vivint', 'home', 'a Vivint alarm or camera', 3),
    VendorRule('assa abloy', 'lock', 'an ASSA ABLOY / Yale lock', 3),
    VendorRule('allegion', 'lock', 'a Schlage lock', 3),
    VendorRule('august home', 'lock', 'an August lock', 3),
    VendorRule('whirlpool', 'home', 'a Whirlpool appliance', 3),
    VendorRule('bsh hausgeraete', 'home', 'a Bosch/Siemens appliance', 3),
    VendorRule('bsh hausgeräte', 'home', 'a Bosch/Siemens appliance', 3),
    VendorRule('haier', 'home', 'a Haier/GE appliance', 2),
    VendorRule('midea', 'home', 'a Midea appliance', 3),
    VendorRule('espressif', 'iot', 'an ESP32/ESP8266-based IoT gadget', 2),
    VendorRule('silicon laboratories', 'iot', 'a Zigbee/Z-Wave smart-home device or smart meter (Silicon Labs chip)', 1),
    VendorRule('texas instruments', 'iot', 'a BLE beacon, asset tag, or fitness tracker (TI chip)', 2),
    VendorRule('nordic semiconductor', 'iot', 'a BLE beacon, fitness tracker, or wearable (Nordic chip)', 2),
    VendorRule('realtek', 'iot', 'a router, TV box, or Wi-Fi IoT gadget (Realtek chip)', 2),
    VendorRule('mediatek', 'iot', 'a router, smart TV, or Wi-Fi IoT gadget (MediaTek chip)', 2),
    VendorRule('murata manufacturing', 'iot', 'a phone, laptop, or IoT product (Murata Wi-Fi/Bluetooth module)', 2),
    VendorRule('quectel', 'iot', 'a cellular IoT device (Quectel module)', 2),
    VendorRule('u-blox', 'iot', 'a GPS/cellular tracker (u-blox module)', 2),
    VendorRule('telit', 'iot', 'a cellular IoT device (Telit module)', 2),
    VendorRule('em microelectronic', 'iot', 'a BLE tag or beacon (EM Micro)', 2),
    VendorRule('tesla inc', 'vehicle', 'a Tesla vehicle or charger', 4),
    VendorRule('tesla,inc', 'vehicle', 'a Tesla vehicle or charger', 4),
    VendorRule('ford motor', 'vehicle', 'a Ford vehicle', 4),
    VendorRule('general motors', 'vehicle', 'a GM vehicle', 4),
    VendorRule('toyota', 'vehicle', 'a Toyota vehicle', 2),
    VendorRule('honda motor', 'vehicle', 'a Honda vehicle', 3),
    VendorRule('volkswagen', 'vehicle', 'a Volkswagen vehicle', 4),
    VendorRule('bmw', 'vehicle', 'a BMW vehicle', 4),
    VendorRule('mercedes', 'vehicle', 'a Mercedes-Benz vehicle', 4),
    VendorRule('denso', 'vehicle', 'a car electronics module (Denso)', 3),
    VendorRule('alps alpine', 'vehicle', 'a car infotainment unit (Alps Alpine)', 3),
    VendorRule('visteon', 'vehicle', 'a car infotainment unit (Visteon)', 3),
    VendorRule('lg innotek', 'vehicle', 'a car telematics module (LG Innotek)', 2),
    VendorRule('samsara', 'vehicle', 'a Samsara fleet tracker or dashcam', 4),
    VendorRule('garmin', 'wearable', 'a Garmin watch or GPS', 3),
    VendorRule('fitbit', 'wearable', 'a Fitbit tracker', 3),
    VendorRule('polar electro', 'wearable', 'a Polar watch', 3),
    VendorRule('oura', 'wearable', 'an Oura ring', 3),
    VendorRule('meta platforms', 'glasses', 'a Meta device (Ray-Ban glasses, Quest)', 3),
    VendorRule('oculus', 'glasses', 'a Meta Quest headset', 3),
    VendorRule('medtronic', 'health', 'a Medtronic medical device', 3),
    VendorRule('abbott', 'health', 'an Abbott medical device', 3),
    VendorRule('omron healthcare', 'health', 'an Omron health monitor', 3),
    VendorRule('withings', 'health', 'a Withings health device', 3),
  ];
}
