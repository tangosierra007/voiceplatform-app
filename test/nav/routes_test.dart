import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/nav/routes.dart';
import 'package:voiceplatform_app/screens/call_placeholders.dart';
import 'package:voiceplatform_app/screens/placeholders.dart';
import 'package:voiceplatform_app/shell/shell_status.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

const _account = SipAccount(
  authUsername: 'mock-202-pixel8',
  password: 'not-a-real-password',
  domain: 'sip.demo-co.example',
  outboundProxy: 'sip:sip.voiceplatform.example:5061;transport=tls',
  displayName: 'Ava Nguyen',
  expiresSeconds: 600,
  instanceId: 'urn:uuid:60000000-0000-4000-8000-000000000001',
);

void main() {
  setUpAll(loadAppFonts);

  Future<FakeCallEngine> engine() async {
    final e = FakeCallEngine(
      outgoing: OutgoingScript.manual,
      registerAfter: Duration.zero,
    );
    await e.start();
    await e.register(_account);
    return e;
  }

  GoRouter router(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Navigator).first))
          .read(routerProvider);

  testWidgets('sign-in route opens without the tab bar', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest());
    await tester.pumpAndSettle();
    router(tester).go(Routes.signIn);
    await tester.pumpAndSettle();
    expect(find.byType(SignInPlaceholder), findsOneWidget);
    expect(find.byType(VpTabBar), findsNothing);
  });

  testWidgets(
    'an incoming call opens Incoming; answering opens In call; hanging up goes back',
    (tester) async {
      usePhone(tester);
      final e = await engine();
      await tester.pumpWidget(await appUnderTest(engine: e));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(VpTabBar),
          matching: find.text('Contacts'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        e.simulateIncoming(
          remoteNumber: '+61355501987',
          remoteName: 'Westgate Supplies',
          info: const IncomingInfo(calledLabel: 'Sales group', repeatCount: 3),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.byType(IncomingCallPlaceholder), findsOneWidget);
      expect(find.text('Westgate Supplies'), findsOneWidget);
      expect(find.byType(VpTabBar), findsNothing);
      // Ink in both themes.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      expect(scaffold.backgroundColor, const Color(0xFF14110F));

      await tester.tap(find.bySemanticsLabel('Answer'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byType(InCallPlaceholder), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Hang up'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byType(InCallPlaceholder), findsNothing);
      expect(find.byType(VpTabBar), findsOneWidget);
      // Back on the tab the user was on.
      expect(find.byType(TabPlaceholder), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TabPlaceholder),
          matching: find.text('Contacts'),
        ),
        findsOneWidget,
      );
      await e.dispose();
    },
  );

  testWidgets('declining or an answer elsewhere clears the incoming screen', (
    tester,
  ) async {
    usePhone(tester);
    final e = await engine();
    await tester.pumpWidget(await appUnderTest(engine: e));
    await tester.pumpAndSettle();
    late String id;
    await tester.runAsync(() async {
      id = e.simulateIncoming(remoteNumber: '+61491570737');
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.byType(IncomingCallPlaceholder), findsOneWidget);
    await tester.runAsync(() async {
      e.simulateAnsweredElsewhere(id);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.byType(IncomingCallPlaceholder), findsNothing);
    expect(find.byType(VpTabBar), findsOneWidget);
    await e.dispose();
  });

  testWidgets('Messages route redirects to Keypad without an SMS line', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest(status: const ShellStatus()));
    await tester.pumpAndSettle();
    router(tester).go(Routes.messages);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(TabPlaceholder),
        matching: find.text('Keypad'),
      ),
      findsOneWidget,
    );
  });
}
