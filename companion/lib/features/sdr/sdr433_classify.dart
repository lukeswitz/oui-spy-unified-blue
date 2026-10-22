enum Sdr433Category { tpms, meter, security, fob, environmental, weather, unknown }

extension Sdr433CategoryLabel on Sdr433Category {
  String get label => switch (this) {
        Sdr433Category.tpms => 'TPMS',
        Sdr433Category.meter => 'Meter',
        Sdr433Category.security => 'Security',
        Sdr433Category.fob => 'Fob',
        Sdr433Category.environmental => 'Environmental',
        Sdr433Category.weather => 'Weather',
        Sdr433Category.unknown => 'Unknown',
      };
}

const _tpmsModels = [
  'tpms', 'schrader', 'steelmate', 'jansite', 'eeztire', 'tyreguard', 'airpuxem',
  'abarth-124', 'shenzhen-egqq85', 'pmv-107j', 'hyundai-vdo', 'audi-pressurealert',
  'bmw-gen', 'gm-aftermarket', 'ave',
];
const _tpmsFields = ['pressure_kpa', 'pressure_psi'];

const _meterModels = [
  'ert-scm', 'scmplus', 'idm', 'netidm', 'neptune-r900', 'badger', 'orion-endpoint',
  'mueller', 'wireless-mbus', 'apator', 'arad', 'landisgyr', 'flowis', 'currentcost',
  'efergy', 'geo-minim', 'esic', 'revolt', 'blueline', 'emontx', 'ec3k',
  'ikea-sparsnas', 'clipsal', 'oregon-cm1',
];
const _meterFields = [
  'consumption_data', 'consumption', 'endpointid', 'ertserialnumber', 'erttype',
  'metertype', 'volume_m3', 'volume_gal', 'energy_kwh', 'power_w', 'cumulative_kwh',
  'consumptionintervalcount',
];

const _securityModels = [
  'dsc-security', 'honeywell-security', 'interlogix', 'kerui', 'chuango', 'cavius',
  'powercode', 'visonic', 'risco', 'simplisafe', 'yale-hsa', 'x10-security', 'cwpirc',
  'generic-motion', 'smoke-', 'govee-contact',
];
const _securityFields = [
  'reed_open', 'contact_open', 'xtamper1', 'xtamper2', 'xactivity', 'motion', 'opened',
  'tamper', 'supervised',
];

const _fobModels = [
  'remote', 'carremote', 'car-remote', 'keyfob', 'keeloq', 'microchip-hcs', 'hcs200',
  'hcs361', 'secplus', 'megacode', 'nice-flor', 'cardin', 'ht680', 'quinetic',
  'proflame2', 'somfy', 'abo1502t', '5wy72xx', 'akhan', 'alps-fwb', 'astrostart',
  'audiovox', 'compustar', 'continental-kr5', 'nidec', 'mic6sc2', 'frdpc2002',
];
const _fobFields = [
  'button_id', 'button_code', 'button_str', 'rbutton', 'rolling', 'fixed', 'remote_id',
  'dipswitch',
];

const _envModels = [
  'oil-', 'ts-ft002', 'opus-xt300', 'springfield-soil', 'homelead', 'rainpoint-soil',
  'sensibleliving', 'rosstech', 'nexus-sauna', 'oria-wa150km', 'acurite-515',
  'acurite-leak', 'acurite-01185m', 'govee-water', 'govee-h5059', 'bresser-leakage',
  'bresser-co2', 'bresser-hchovoc', 'maverick', 'thermopro-tp', 'burnhard', 'gasmate',
];
const _envFields = [
  'depth_cm', 'moisture', 'detect_wet', 'leak_detected', 'leaking', 'pm2_5_ug_m3',
  'pm10_ug_m3', 'co2_ppm', 'hcho_ppb', 'voc_level',
];

const _weatherModels = [
  'acurite', 'oregon', 'lacrosse', 'fineoffset', 'ambient', 'ecowitt', 'bresser',
  'nexus', 'prologue', 'rubicson', 'auriol', 'tfa', 'alecto', 'archos', 'atech',
  'baldr', 'biltema', 'calibeur', 'celsia', 'cotech', 'digitech', 'eurochron',
  'esperanza', 'geevon', 'gt-wt', 'hideki', 'holman', 'inkbird', 'inovalley', 'kedsum',
  'klimalogg', 'missil', 'norgo', 'philips', 'sainlogic', 'schou', 'sharp-spc',
  'solight', 'telldus', 'thermor', 'vauno', 'vevor', 'ws2032', 'wt450', 'thermopro-tx',
  'infactory', 'nexus-th',
];
const _weatherFields = [
  'temperature_c', 'temperature_f', 'humidity', 'rain_mm', 'rain_in', 'rain_rate_mm_h',
  'wind_avg_km_h', 'wind_max_km_h', 'wind_avg_m_s', 'wind_dir_deg', 'uvi', 'uv_index',
  'light_lux', 'strike_count', 'storm_dist_km', 'pressure_hpa',
];

bool _anySub(String model, List<String> subs) => subs.any(model.contains);
bool _anyKey(Set<String> fkeys, List<String> keys) => keys.any(fkeys.contains);

Sdr433Category classify433(String model, Iterable<String> fieldKeys, {String devType = ''}) {
  final m = model.toLowerCase();
  final dt = devType.toLowerCase();
  final fkeys = fieldKeys.map((k) => k.toLowerCase()).toSet();
  if (dt == 'tpms' || _anyKey(fkeys, _tpmsFields) || _anySub(m, _tpmsModels)) return Sdr433Category.tpms;
  if (_anyKey(fkeys, _meterFields) || _anySub(m, _meterModels)) return Sdr433Category.meter;
  if (_anySub(m, _securityModels) || _anyKey(fkeys, _securityFields)) return Sdr433Category.security;
  if (_anySub(m, _fobModels) || _anyKey(fkeys, _fobFields)) return Sdr433Category.fob;
  if (_anySub(m, _envModels) || _anyKey(fkeys, _envFields)) return Sdr433Category.environmental;
  if (_anySub(m, _weatherModels) || _anyKey(fkeys, _weatherFields)) return Sdr433Category.weather;
  return Sdr433Category.unknown;
}

class VehicleHint {
  final String make;
  final String vehicles;
  final String region;
  final String freq;
  const VehicleHint(this.make, this.vehicles, this.region, this.freq);

  String get text => '$make — $vehicles [$region ${freq}MHz]';
}

const _vehicleDb = <(String, VehicleHint)>[
  ('schrader-smd3ma4', VehicleHint('Subaru / Nissan / Infiniti', 'Subaru WRX/Impreza, some Nissan/Infiniti, Renault', 'US/EU', '433')),
  ('schrader-eg53ma4', VehicleHint('GM / Opel / Vauxhall / Saab', 'Chevrolet, Opel/Vauxhall, Saab', 'US/EU', '433')),
  ('schrader', VehicleHint('Schrader/Sensata GG4 (approx)', 'early-mid 2000s US/EU OEM, multi-make (FCC MRXGG4)', 'US/EU', '315/433')),
  ('pmv-107j', VehicleHint('Toyota / Lexus / Scion (Pacific PMV-107J)', 'Camry, Corolla, RAV4, Prius, Highlander, Tacoma; Lexus ES/GS/IS', 'US', '315')),
  ('toyota', VehicleHint('Toyota (Pacific PMV)', 'Auris, Corolla, RAV4, Yaris, etc.', 'EU/JP', '433')),
  ('ford', VehicleHint('Ford (Continental VDO)', 'Fiesta, Focus, Kuga, Escape, Transit', 'US/EU', '315/433')),
  ('renault-0435r', VehicleHint('Renault (VDO S180052064Z)', 'Fluence, Laguna III, Latitude, Megane III, Scenic III, Zoe', 'EU', '433')),
  ('renault', VehicleHint('Renault / Dacia', 'Clio, Captur, Zoe, Dacia Sandero', 'EU', '433')),
  ('citroen', VehicleHint('PSA (Citroen/Peugeot)', 'Citroen, Peugeot, likely Fiat/Mitsubishi (VDO)', 'EU', '433')),
  ('hyundai-vdo', VehicleHint('Hyundai / Kia (Continental VDO TG1C)', 'Hyundai i30 PDE; similar Conti sensors on BMW/FCA/PSA/Mitsubishi/Mazda', 'EU', '433')),
  ('elantra2012', VehicleHint('Hyundai / Honda (TRW GQ4-44T)', 'Hyundai Elantra/Genesis, Honda Civic', 'US', '315')),
  ('kia', VehicleHint('Kia (Pacific)', 'Kia Rio III 2011-2017, some Hyundai', 'EU/US', '433')),
  ('audi-pressurealert', VehicleHint('Audi', 'Audi (pressure-alert; BMW Gen4/5 protocol)', 'EU', '433')),
  ('bmw', VehicleHint('BMW / Audi (HUF/Conti/Schrader)', 'BMW Gen2-Gen5, Audi', 'EU', '433')),
  ('porsche', VehicleHint('Porsche', '987 Boxster/Cayman Gen2', 'EU', '433')),
  ('nissan', VehicleHint('Nissan', 'Nissan (various)', 'US/EU', '315/433')),
  ('trw', VehicleHint('FCA (Chrysler/Jeep/RAM/Dodge)', 'Chrysler/Jeep/RAM/Dodge 2014-2022 (GQ4-70T)', 'US', '433')),
  ('gm', VehicleHint('GM aftermarket', 'Chevrolet, GMC, Buick, Cadillac aftermarket sensors', 'US', '315/433')),
  ('abarth', VehicleHint('Abarth/Fiat / Mazda (VDO TG1C)', 'Fiat/Abarth 124 Spider, Mazda MX-5 ND', 'EU', '433')),
  ('truck', VehicleHint('Heavy truck (aftermarket solar)', 'generic 6-sensor truck/trailer TPMS', 'global', '433')),
  ('jansite', VehicleHint('Jansite (aftermarket)', 'universal clamp-on / solar TPMS', 'global', '433')),
  ('eeztire', VehicleHint('EezTire/TST (aftermarket RV)', 'RV/trailer TPMS (E618, TST-507)', 'US', '433')),
  ('tyreguard', VehicleHint('Davies Craig TyreGuard', 'aftermarket caravan/trailer', 'EU/AU', '434')),
  ('steelmate', VehicleHint('Steelmate (aftermarket)', 'universal TP-S series', 'global', '433')),
  ('airpuxem', VehicleHint('Airpuxem (aftermarket SENASIC)', 'universal TYH11', 'global', '433')),
  ('ave', VehicleHint('AVE (aftermarket)', 'universal', 'EU', '433')),
];

VehicleHint? identifyVehicle(String? model) {
  final m = (model ?? '').toLowerCase();
  if (m.isEmpty) return null;
  for (final (key, rec) in _vehicleDb) {
    if (m.contains(key)) return rec;
  }
  return null;
}
