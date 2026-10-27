import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

Future<ProviderContainer> _container(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUpAll(loadAppFonts);

  test('defaults to System', () async {
    final c = await _container({});
    expect(c.read(themePreferenceProvider), ThemePreference.system);
    expect(c.read(themePreferenceProvider).mode, ThemeMode.system);
  });

  test('reads and stores the override', () async {
    final c = await _container({ThemePreferenceNotifier.storageKey: 'dark'});
    expect(c.read(themePreferenceProvider), ThemePreference.dark);
    await c.read(themePreferenceProvider.notifier).set(ThemePreference.light);
    final sp = c.read(sharedPreferencesProvider);
    expect(sp.getString(ThemePreferenceNotifier.storageKey), 'light');
    await c.read(themePreferenceProvider.notifier).set(ThemePreference.system);
    expect(sp.getString(ThemePreferenceNotifier.storageKey), isNull);
  });

  test('an unknown stored value falls back to System', () async {
    final c = await _container({ThemePreferenceNotifier.storageKey: 'sepia'});
    expect(c.read(themePreferenceProvider), ThemePreference.system);
  });

  testWidgets('System follows the device brightness', (tester) async {
    usePhone(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(await appUnderTest());
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Keypad').first)).brightness,
      Brightness.dark,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Keypad').first)).brightness,
      Brightness.light,
    );
  });

  testWidgets('a stored Light wins over a dark device', (tester) async {
    usePhone(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(await appUnderTest(theme: ThemePreference.light));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Keypad').first)).brightness,
      Brightness.light,
    );
  });
}
