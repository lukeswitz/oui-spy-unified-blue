import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ignore_list_state.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('alert and ignore-list notifications do not rebuild app state', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final before = container.read(appStateProvider);
    container.read(notificationServiceProvider).notifyListeners();
    container.read(ignoreListProvider).notifyListeners();
    await Future<void>.delayed(Duration.zero);
    expect(identical(container.read(appStateProvider), before), isTrue);
  });
}
