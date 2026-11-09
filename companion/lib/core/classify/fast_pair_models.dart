class FastPairModel {
  final String name;
  final String maker;
  final String type;
  final bool tracking;
  const FastPairModel(this.name, this.maker, this.type, this.tracking);

  String get bucket => switch (type) {
        'HEADPHONES' || 'TRUE_WIRELESS_HEADPHONES' => 'audio-personal',
        'SPEAKER' => 'audio-speaker',
        'WEAR_OS' || 'WEARABLE' => 'wearable',
        'AUTOMOTIVE' || 'ANDROID_AUTO' => 'vehicle',
        'INPUT_DEVICE' || '17' => 'hid',
        '11' => 'tag',
        '13' => 'phone',
        '12' => 'computer',
        '16' => 'printer',
        '10' => 'glasses',
        _ => 'audio-personal',
      };
}

class FastPairModels {
  FastPairModels._();

  static const asset = 'assets/fast_pair/model_ids.csv';

  static final models = <int, FastPairModel>{};

  static void load(String csv) {
    models.clear();
    for (final line in csv.split('\n').skip(1)) {
      final f = _fields(line.trimRight());
      if (f.length < 6) continue;
      final id = int.tryParse(f[0]);
      final name = f[1].trim().isNotEmpty ? f[1].trim() : f[4].trim();
      if (id == null || name.isEmpty) continue;
      models[id] = FastPairModel(name, f[2].trim(), f[3].trim(), f[5].trim().toUpperCase() == 'TRUE');
    }
  }

  static List<String> _fields(String line) {
    final out = <String>[];
    final cur = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (quoted) {
        if (c != '"') {
          cur.write(c);
        } else if (i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(c);
      }
    }
    out.add(cur.toString());
    return out;
  }
}
