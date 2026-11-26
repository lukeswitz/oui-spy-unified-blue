// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/assistant/assistant_auto.dart';
import 'package:oui_spy/core/assistant/assistant_grants.dart';
import 'package:oui_spy/core/assistant/assistant_intel.dart';
import 'package:oui_spy/core/assistant/assistant_llm.dart';
import 'package:oui_spy/core/assistant/assistant_reports.dart';
import 'package:oui_spy/core/assistant/assistant_settings.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/watch_alert_log.dart';
import 'package:oui_spy/features/assistant/assistant_settings_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_chat_test.dart' show ScriptedLlm;
import 'assistant_llm_test.dart' show MemKeys;
import 'assistant_tools_test.dart' show FakeEnv;

class ManyEnv extends FakeEnv {
  ManyEnv(this.n);
  final int n;

  @override
  List<Map<String, dynamic>> devices() => [
        for (var i = 0; i < n; i++)
          {'mac': macOf(i), 'name': 'D$i', 'maker': 'Acme', 'type': 'camera', 'lat': 10.123456, 'lon': 20.123456},
      ];
}

String macOf(int i) => 'AA:BB:CC:00:${(i ~/ 256).toRadixString(16).padLeft(2, '0').toUpperCase()}:${(i % 256).toRadixString(16).padLeft(2, '0').toUpperCase()}';

class FakeClock {
  FakeClock(this.ms);
  int ms;
  DateTime call() => DateTime.fromMillisecondsSinceEpoch(ms);
}

LlmReply note(String t) => LlmReply(t, const []);

const readySettings = AssistantSettings(
  provider: LlmKind.ollama,
  models: {LlmKind.ollama: 'm'},
  ollamaUrl: 'http://192.0.2.10:11434',
);

AssistantAccess granted(Set<AssistantGrant> g, {bool on = true}) => AssistantAccess(on: on, granted: g);

({AssistantAutoIntel auto, AssistantIntel intel, ScriptedLlm llm, List<Duration> waits, FakeClock clock}) autoIntel({
  int devices = 3,
  bool enabled = true,
  bool ready = true,
  AssistantAccess? access,
  int startMs = 1000000,
}) {
  final llm = ScriptedLlm([note('Maker: Acme')]);
  final acc = access ?? granted({AssistantGrant.devices});
  final clock = FakeClock(startMs);
  final waits = <Duration>[];
  final intel = AssistantIntel(access: () => acc, provider: () async => llm, env: ManyEnv(devices), modelLabel: () => 'Test');
  final auto = AssistantAutoIntel(
    intel: intel,
    enabled: () => enabled,
    ready: () => ready,
    access: () => acc,
    clock: clock.call,
    wait: (d) async {
      waits.add(d);
      clock.ms += d.inMilliseconds;
    },
  );
  return (auto: auto, intel: intel, llm: llm, waits: waits, clock: clock);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('settings', () {
    test('both are off by default', () async {
      expect(const AssistantSettings().autoIntel, isFalse);
      expect(const AssistantSettings().reportEvery, ReportEvery.off);
      final n = AssistantSettingsNotifier(MemKeys());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(n.state.autoIntel, isFalse);
      expect(n.state.reportEvery, ReportEvery.off);
      expect(n.state.reportHours, 6);
      expect(n.state.reportDailyMinutes, 480);
    });

    test('auto intel and the schedule persist, and the schedule restarts from now', () async {
      final clock = FakeClock(5000000);
      final n = AssistantSettingsNotifier(MemKeys(), clock: clock.call);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await n.setAutoIntel(true);
      await n.setReportSchedule(every: ReportEvery.daily, dailyMinutes: 8 * 60 + 30);
      expect(n.state.reportLastMs, 5000000);
      clock.ms = 6000000;
      await n.setReportSchedule(every: ReportEvery.every, hours: 12);
      expect(n.state.reportLastMs, 6000000);
      await n.setReportSchedule(every: ReportEvery.off);
      expect(n.state.reportLastMs, 6000000);

      final again = AssistantSettingsNotifier(MemKeys());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(again.state.autoIntel, isTrue);
      expect(again.state.reportEvery, ReportEvery.off);
      expect(again.state.reportHours, 12);
      expect(again.state.reportDailyMinutes, 510);
      expect(again.state.reportLastMs, 6000000);
    });

    test('a change made before the load finishes is not overwritten', () async {
      SharedPreferences.setMockInitialValues({AssistantSettingsNotifier.keyAutoIntel: false});
      final n = AssistantSettingsNotifier(MemKeys());
      await n.setAutoIntel(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(n.state.autoIntel, isTrue);
    });
  });

  group('auto intel', () {
    test('does nothing while off', () async {
      final t = autoIntel(enabled: false);
      t.auto.offer(macOf(0));
      await t.auto.drain();
      expect(t.llm.sent, isEmpty);
      expect(t.intel.notes, isEmpty);
    });

    test('does nothing without DEVICES or while the assistant is off', () async {
      for (final a in [granted({AssistantGrant.drones}), granted({AssistantGrant.devices}, on: false)]) {
        final t = autoIntel(access: a);
        t.auto.offer(macOf(0));
        await t.auto.drain();
        expect(t.llm.sent, isEmpty);
      }
    });

    test('does nothing without a ready provider', () async {
      final t = autoIntel(ready: false);
      t.auto.offer(macOf(0));
      await t.auto.drain();
      expect(t.llm.sent, isEmpty);
      expect(t.intel.notes, isEmpty);
    });

    test('looks a device up once, stores the note like a manual one and sends no position', () async {
      final t = autoIntel();
      t.auto.offer(macOf(1).toLowerCase());
      await t.auto.drain();
      expect(t.llm.sent, hasLength(1));
      expect(t.intel.notes[macOf(1)]!.text, 'Maker: Acme');
      expect(t.intel.notes[macOf(1)]!.model, 'Test');
      final input = (t.llm.sent.first.first as UserTurn).text;
      expect(input, isNot(contains('10.123456')));
      expect(input, isNot(contains('20.123456')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AssistantIntel.prefKey), contains('Maker: Acme'));
    });

    test('skips a device that already has a note and one the app does not know', () async {
      final t = autoIntel();
      await t.intel.lookInto(macOf(0));
      expect(t.llm.sent, hasLength(1));
      t.auto.offer(macOf(0));
      t.auto.offer('AA:BB:CC:FF:FF:FF');
      await t.auto.drain();
      expect(t.llm.sent, hasLength(1));
      expect(t.auto.runsToday, 0);
    });

    test('keeps at least 20 s between runs', () async {
      final t = autoIntel();
      for (var i = 0; i < 3; i++) {
        t.auto.offer(macOf(i));
      }
      await t.auto.drain();
      expect(t.llm.sent, hasLength(3));
      expect(t.waits, [const Duration(seconds: 20), const Duration(seconds: 20)]);
    });

    test('stops at 40 a day, then runs again once a day has passed', () async {
      final t = autoIntel(devices: 60);
      for (var i = 0; i < 45; i++) {
        t.auto.offer(macOf(i));
      }
      await t.auto.drain();
      expect(t.llm.sent, hasLength(40));
      expect(t.intel.notes, hasLength(40));
      expect(t.auto.queued, 0);
      expect(t.auto.runsToday, 40);

      t.auto.offer(macOf(50));
      await t.auto.drain();
      expect(t.llm.sent, hasLength(40));

      t.clock.ms += 24 * 3600000 + 1;
      t.auto.offer(macOf(50));
      await t.auto.drain();
      expect(t.llm.sent, hasLength(41));
    });

    test('the daily count survives a restart', () async {
      final t = autoIntel(devices: 60);
      for (var i = 0; i < 40; i++) {
        t.auto.offer(macOf(i));
      }
      await t.auto.drain();
      expect(t.llm.sent, hasLength(40));

      final llm2 = ScriptedLlm([note('x')]);
      final intel2 = AssistantIntel(access: () => granted({AssistantGrant.devices}), provider: () async => llm2, env: ManyEnv(60), modelLabel: () => 'Test');
      final auto2 = AssistantAutoIntel(
        intel: intel2,
        enabled: () => true,
        ready: () => true,
        access: () => granted({AssistantGrant.devices}),
        clock: t.clock.call,
        wait: (d) async => t.clock.ms += d.inMilliseconds,
      );
      auto2.offer(macOf(55));
      await auto2.drain();
      expect(llm2.sent, isEmpty);
    });

    test('switching it off drops what is queued', () async {
      var on = true;
      final llm = ScriptedLlm([note('x')]);
      final clock = FakeClock(1000000);
      final acc = granted({AssistantGrant.devices});
      final intel = AssistantIntel(access: () => acc, provider: () async => llm, env: ManyEnv(5), modelLabel: () => 'Test');
      final auto = AssistantAutoIntel(
        intel: intel,
        enabled: () => on,
        ready: () => true,
        access: () => acc,
        clock: clock.call,
        wait: (d) async {
          on = false;
          clock.ms += d.inMilliseconds;
        },
      );
      for (var i = 0; i < 4; i++) {
        auto.offer(macOf(i));
      }
      await auto.drain();
      expect(llm.sent, hasLength(1));
      expect(auto.queued, 0);
    });

    test('only alerts newer than the start count', () async {
      final t = autoIntel();
      final start = t.clock.ms;
      t.auto.onAlerts([
        {'macAddress': macOf(0), 'appTimestamp': start - 10},
        {'macAddress': macOf(1), 'appTimestamp': start + 5},
        {'macAddress': macOf(2), 'appTimestamp': start + 9},
      ]);
      await t.auto.drain();
      expect(t.intel.notes.keys.toSet(), {macOf(1), macOf(2)});
      t.auto.onAlerts([
        {'macAddress': macOf(1), 'appTimestamp': start + 5},
        {'macAddress': macOf(2), 'appTimestamp': start + 9},
      ]);
      await t.auto.drain();
      expect(t.llm.sent, hasLength(2));
    });
  });

  group('scheduled reports', () {
    final noon = DateTime(2026, 6, 10, 12);

    AssistantSettings every(int lastMs, {int hours = 6}) =>
        readySettings.copyWith(reportEvery: ReportEvery.every, reportHours: hours, reportLastMs: lastMs);

    test('next run: off is none, every counts from the last run, daily is the next time of day after it', () {
      expect(nextReportAt(readySettings, noon), isNull);
      expect(nextReportAt(every(noon.millisecondsSinceEpoch, hours: 4), noon), DateTime(2026, 6, 10, 16));
      expect(nextReportAt(every(0), noon), DateTime(2026, 6, 10, 18));
      final daily = readySettings.copyWith(reportEvery: ReportEvery.daily, reportDailyMinutes: 8 * 60, reportLastMs: noon.millisecondsSinceEpoch);
      expect(nextReportAt(daily, noon), DateTime(2026, 6, 11, 8));
      final early = daily.copyWith(reportLastMs: DateTime(2026, 6, 10, 7).millisecondsSinceEpoch);
      expect(nextReportAt(early, noon), DateTime(2026, 6, 10, 8));
    });

    test('the window covers the time since the last run, at most 7 days, 24 h when never run', () {
      expect(reportWindowHours(every(0), noon), 24);
      expect(reportWindowHours(every(noon.subtract(const Duration(hours: 7, minutes: 1)).millisecondsSinceEpoch), noon), 8);
      expect(reportWindowHours(every(noon.subtract(const Duration(days: 30)).millisecondsSinceEpoch), noon), 168);
    });

    ({AssistantSchedule schedule, ScriptedLlm llm, AssistantReports reports, List<int> ran, FakeClock clock}) rig(
      AssistantSettings s, {
      AssistantAccess? access,
      DateTime? now,
    }) {
      final clock = FakeClock((now ?? noon).millisecondsSinceEpoch);
      final acc = access ?? granted({AssistantGrant.devices});
      final llm = ScriptedLlm([note('Quiet.')]);
      final reports = AssistantReports(access: () => acc, provider: () async => llm, env: FakeEnv(), modelLabel: () => 'Test', clock: clock.call);
      final ran = <int>[];
      final schedule = AssistantSchedule(reports: reports, access: () => acc, settings: () => s, markRan: (ms) async => ran.add(ms), clock: clock.call);
      return (schedule: schedule, llm: llm, reports: reports, ran: ran, clock: clock);
    }

    test('does nothing while off', () async {
      final r = rig(readySettings);
      expect(await r.schedule.check(), isFalse);
      expect(r.llm.sent, isEmpty);
    });

    test('does nothing when the first run is not due yet', () async {
      final r = rig(every(0));
      expect(await r.schedule.check(), isFalse);
      expect(r.llm.sent, isEmpty);
    });

    test('catches up once when a run was missed', () async {
      final last = noon.subtract(const Duration(hours: 30));
      final r = rig(every(last.millisecondsSinceEpoch));
      expect(await r.schedule.check(), isTrue);
      expect(r.llm.sent, hasLength(1));
      expect(r.reports.reports.single.hours, 30);
      expect(r.reports.reports.single.text, 'Quiet.');
      expect(r.ran, [noon.millisecondsSinceEpoch]);
    });

    test('runs again only after the interval from the last run', () async {
      var s = every(noon.subtract(const Duration(hours: 7)).millisecondsSinceEpoch);
      final r = rig(s);
      expect(await r.schedule.check(), isTrue);
      s = every(r.ran.single);
      final again = AssistantSchedule(reports: r.reports, access: () => granted({AssistantGrant.devices}), settings: () => s, markRan: (ms) async => r.ran.add(ms), clock: r.clock.call);
      expect(await again.check(), isFalse);
      r.clock.ms += 6 * 3600000 + 1;
      expect(await again.check(), isTrue);
      expect(r.llm.sent, hasLength(2));
    });

    test('daily catches up after the app was closed past the set time', () async {
      final s = readySettings.copyWith(
        reportEvery: ReportEvery.daily,
        reportDailyMinutes: 8 * 60,
        reportLastMs: DateTime(2026, 6, 9, 20).millisecondsSinceEpoch,
      );
      final late = rig(s, now: DateTime(2026, 6, 10, 9));
      expect(await late.schedule.check(), isTrue);
      final early = rig(s, now: DateTime(2026, 6, 10, 7));
      expect(await early.schedule.check(), isFalse);
    });

    test('does nothing without the assistant on, a ready provider or any data grant', () async {
      final last = noon.subtract(const Duration(hours: 30)).millisecondsSinceEpoch;
      final off = rig(every(last), access: granted({AssistantGrant.devices}, on: false));
      expect(await off.schedule.check(), isFalse);
      final noGrant = rig(every(last), access: granted({AssistantGrant.files}));
      expect(await noGrant.schedule.check(), isFalse);
      final noProvider = rig(every(last).copyWith(clearProvider: true));
      expect(await noProvider.schedule.check(), isFalse);
      final cloudNotAcked = rig(every(last).copyWith(
        provider: LlmKind.claude,
        models: {LlmKind.claude: 'm'},
        hasKey: {LlmKind.claude},
      ));
      expect(await cloudNotAcked.schedule.check(), isFalse);
      for (final r in [off, noGrant, noProvider, cloudNotAcked]) {
        expect(r.llm.sent, isEmpty);
        expect(r.ran, isEmpty);
      }
    });
  });

  group('provider wiring', () {
    test('a new alert in the feed starts a lookup only once the switch, grants and provider are on', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final prefs = await SharedPreferences.getInstance();
      final llm = ScriptedLlm([note('Maker: Acme')]);
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantKeyStoreProvider.overrideWithValue(MemKeys()),
        assistantIntelProvider.overrideWith((ref) => AssistantIntel(
              access: () => ref.read(assistantAccessProvider),
              provider: () async => llm,
              env: ManyEnv(3),
              modelLabel: () => 'Test',
            )),
      ]);
      addTearDown(c.dispose);
      final auto = c.read(assistantAutoProvider);
      final feed = c.read(alertsFeedProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final at = DateTime.now().millisecondsSinceEpoch + 1000;

      Future<void> alert(String mac, int t) async {
        await db.insertClassAlert(
          macAddress: mac,
          deviceName: '',
          alertClass: 'camera',
          title: 'T',
          reason: 'R',
          isBle: true,
          rssi: -50,
          channel: 0,
          alertedAt: t,
        );
        await feed.reload();
        await auto.intel.drain();
      }

      await alert(macOf(0), at);
      expect(llm.sent, isEmpty);

      await c.read(assistantAccessProvider.notifier).setOn(true);
      await c.read(assistantAccessProvider.notifier).setGrant(AssistantGrant.devices, true);
      await c.read(assistantSettingsProvider.notifier).setAutoIntel(true);
      await alert(macOf(1), at + 10);
      expect(llm.sent, isEmpty);

      final s = c.read(assistantSettingsProvider.notifier);
      await s.setProvider(LlmKind.ollama);
      await s.setModel(LlmKind.ollama, 'm');
      await s.setOllamaUrl('192.0.2.10');
      await alert(macOf(2), at + 20);
      expect(llm.sent, hasLength(1));
      expect(c.read(assistantIntelProvider).notes.keys, [macOf(2)]);
    });
  });

  group('settings screen', () {
    Future<ProviderContainer> pump(WidgetTester tester, {LlmKind? provider}) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      final c = ProviderContainer(overrides: [assistantKeyStoreProvider.overrideWithValue(MemKeys())]);
      addTearDown(c.dispose);
      await c.read(assistantAccessProvider.notifier).setOn(true);
      if (provider != null) await c.read(assistantSettingsProvider.notifier).setProvider(provider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: SingleChildScrollView(child: AssistantAutoSection()))),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('both start off; switching intel on warns, naming the cloud provider, and CANCEL keeps it off', (tester) async {
      final c = await pump(tester, provider: LlmKind.claude);
      expect(c.read(assistantSettingsProvider).autoIntel, isFalse);
      expect(find.text('Off: no reports until you set when they come.'), findsOneWidget);

      await tester.tap(find.text('Look into new alerts automatically'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Anthropic'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(c.read(assistantSettingsProvider).autoIntel, isFalse);

      await tester.tap(find.text('Look into new alerts automatically'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SWITCH ON'));
      await tester.pumpAndSettle();
      expect(c.read(assistantSettingsProvider).autoIntel, isTrue);

      await tester.tap(find.text('Look into new alerts automatically'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(c.read(assistantSettingsProvider).autoIntel, isFalse);
    });

    testWidgets('a local provider is named as your Ollama server', (tester) async {
      await pump(tester, provider: LlmKind.ollama);
      await tester.tap(find.text('Write a report automatically'));
      await tester.pumpAndSettle();
      expect(find.textContaining('your Ollama server'), findsOneWidget);
      expect(find.textContaining('Anthropic'), findsNothing);
    });

    testWidgets('reports: switching on asks, then Every and Daily show their choices', (tester) async {
      final c = await pump(tester, provider: LlmKind.ollama);
      await tester.tap(find.text('Write a report automatically'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SWITCH ON'));
      await tester.pumpAndSettle();
      expect(c.read(assistantSettingsProvider).reportEvery, ReportEvery.every);
      expect(c.read(assistantSettingsProvider).reportLastMs, greaterThan(0));
      expect(find.text('REPORTS COME'), findsOneWidget);
      for (final h in reportEveryHours) {
        expect(find.text('$h h'), findsOneWidget);
      }

      await tester.tap(find.text('12 h'));
      await tester.pumpAndSettle();
      expect(c.read(assistantSettingsProvider).reportHours, 12);

      await tester.tap(find.text('Daily'));
      await tester.pumpAndSettle();
      expect(c.read(assistantSettingsProvider).reportEvery, ReportEvery.daily);
      expect(find.text('At 8:00 AM'), findsOneWidget);
      expect(find.text('6 h'), findsNothing);

      await tester.tap(find.text('Write a report automatically'));
      await tester.pumpAndSettle();
      expect(c.read(assistantSettingsProvider).reportEvery, ReportEvery.off);
    });

    testWidgets('the switches are locked while the assistant is off', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      final c = ProviderContainer(overrides: [assistantKeyStoreProvider.overrideWithValue(MemKeys())]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: SingleChildScrollView(child: AssistantAutoSection()))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Look into new alerts automatically'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(c.read(assistantSettingsProvider).autoIntel, isFalse);
    });
  });
}
