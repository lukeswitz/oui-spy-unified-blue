const _makerPrefixes = <String, String>{
  '1581F': 'DJI',
  '1748C': 'Autel Robotics',
  '1701A': 'Percepto',
  '1587A': 'AgEagle',
  '1785': 'Watts Innovations',
};

String? cta2063Maker(String serial, {int? idType}) {
  if (idType != null && idType != 1) return null;
  final s = serial.trim().toUpperCase();
  String? best;
  var len = 0;
  for (final e in _makerPrefixes.entries) {
    if (e.key.length > len && s.startsWith(e.key)) {
      best = e.value;
      len = e.key.length;
    }
  }
  return best;
}
