import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/features/wardrive/session_launch.dart';

class _FakePhone extends ChangeNotifier implements PhoneBleSource {
  bool on = false;

  @override
  bool get active => on;

  @override
  void setActive(bool v) {
    on = v;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePhone phone;
  final results = <bool>[];

  Future<void> pump(WidgetTester tester, {bool explicit = false}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [phoneBleSourceProvider.overrideWith((ref) => phone)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async =>
                  results.add(await ensurePhoneScan(context, ref, explicit: explicit)),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
  }

  setUp(() {
    phone = _FakePhone();
    results.clear();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('asks once; NOT NOW points to the phone icon and is never asked again', (tester) async {
    await pump(tester);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Scan with this phone?'), findsOneWidget);

    await tester.tap(find.text('NOT NOW'));
    await tester.pumpAndSettle();
    expect(results, [false]);
    expect(phone.on, isFalse);
    expect(find.textContaining('icon at the top'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Scan with this phone?'), findsNothing);
    expect(results, [false, false]);
    expect(phone.on, isFalse);
  });

  testWidgets('answering SCAN enables phone scan and is never asked again', (tester) async {
    await pump(tester);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SCAN'));
    await tester.pumpAndSettle();
    expect(results, [true]);
    expect(phone.on, isTrue);

    phone.setActive(false);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Scan with this phone?'), findsNothing);
    expect(results, [true, false]);
  });

  testWidgets('explicit enable never shows the dialog', (tester) async {
    await pump(tester, explicit: true);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Scan with this phone?'), findsNothing);
    expect(results, [true]);
    expect(phone.on, isTrue);
  });
}
