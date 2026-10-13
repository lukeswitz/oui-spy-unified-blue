import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_api.dart';

void main() {
  final hist = {
    'uploads': [
      {
        'created_at': '2026-09-22 14:16:09.638475+00',
        'filename': 'wardrive_abc.csv.gz',
        'endpoint': 'upload-csv',
        'status': 'done',
        'result': '{"imported": 308864, "captured": 3392, "duplicates": 134753}',
      },
      {
        'filename': 'older.csv',
        'status': 'done',
        'result': {'imported': 1},
      },
    ],
  };

  test('upload-history entry is matched by uploaded filename and its string result decodes', () {
    final e = WdgwarsApi.historyEntryFor(hist, 'wardrive_abc.csv.gz')!;
    final r = WdgwarsUploadResult.fromJson({...WdgwarsApi.resultMapOf(e['result']), 'job_id': '42'});
    expect(r.summary, '308864 imported · 3392 new');
  });

  test('server-side name without .gz still matches', () {
    expect(WdgwarsApi.historyEntryFor(hist, 'older.csv.gz')?['filename'], 'older.csv');
  });

  test('no match returns null', () {
    expect(WdgwarsApi.historyEntryFor(hist, 'missing.csv.gz'), isNull);
    expect(WdgwarsApi.historyEntryFor({'ok': false}, 'x.csv.gz'), isNull);
  });
}
