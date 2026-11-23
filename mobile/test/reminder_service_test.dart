import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest/habits_data.dart';
import 'package:habitquest/main.dart';
import 'package:habitquest/reminders.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'fixtures.dart';

void main() {
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late ReminderService service;
  late bool notificationsAllowed;
  late bool exactAllowed;
  late bool channelBlocked;
  late bool showFails;
  late bool exactRequestGranted;
  late List<MethodCall> calls;

  Dashboard dashboard() => Dashboard.fromJson(
    dashboardFixture([
      {...habitFixture(), 'completed_today': false, 'reminder_time': '23:59'},
    ]),
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    notificationsAllowed = true;
    exactAllowed = true;
    channelBlocked = false;
    showFails = false;
    exactRequestGranted = true;
    calls = [];
    service = ReminderService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'show' && showFails) {
            throw PlatformException(code: 'notification_failed');
          }
          return switch (call.method) {
            'initialize' => true,
            'areNotificationsEnabled' ||
            'requestNotificationsPermission' => notificationsAllowed,
            'canScheduleExactNotifications' => exactAllowed,
            'requestExactAlarmsPermission' =>
              exactAllowed = exactRequestGranted,
            'getNotificationChannels' => [
              {
                'id': 'habitquest_reminders',
                'name': 'Lembretes de hábitos',
                'importance': channelBlocked ? 0 : 3,
                'showBadge': true,
                'bypassDnd': false,
                'playSound': true,
                'enableLights': false,
                'enableVibration': true,
                'ledColor': 0,
                'audioAttributesUsage': 5,
              },
            ],
            'cancelAllPendingNotifications' ||
            'zonedSchedule' ||
            'show' => null,
            _ => throw UnsupportedError('Unexpected method: ${call.method}'),
          };
        });
  });

  tearDown(() {
    service.close();
    debugDefaultTargetPlatformOverride = null;
  });

  test('uses exact scheduling when Android permits it', () async {
    await service.sync(dashboard());
    final scheduled = calls.where((call) => call.method == 'zonedSchedule');
    expect(scheduled, isNotEmpty);
    expect(
      scheduled.every(
        (call) =>
            (call.arguments as Map)['platformSpecifics']['scheduleMode'] ==
            'exactAllowWhileIdle',
      ),
      isTrue,
    );
    expect(service.error, isNull);
  });

  test('background sync never requests exact alarm permission', () async {
    exactAllowed = false;
    await service.sync(dashboard());
    expect(
      calls.any((call) => call.method == 'requestExactAlarmsPermission'),
      isFalse,
    );
    final scheduled = calls.where((call) => call.method == 'zonedSchedule');
    expect(scheduled, isNotEmpty);
    expect(
      scheduled.every(
        (call) =>
            (call.arguments as Map)['platformSpecifics']['scheduleMode'] ==
            'inexactAllowWhileIdle',
      ),
      isTrue,
    );
    expect(service.limitation, contains('atrasar'));
  });

  test('explicit activation requests exact alarm access', () async {
    exactAllowed = false;
    expect(await service.enable(), isNull);
    expect(
      calls.any((call) => call.method == 'requestExactAlarmsPermission'),
      isTrue,
    );
  });

  test(
    'blocked reminder channel reports an error instead of success',
    () async {
      channelBlocked = true;
      await service.sync(dashboard());
      expect(await service.enable(), contains('Lembretes de hábitos'));
      expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
    },
  );

  test(
    'denying exact access retains inexact reminders with a warning',
    () async {
      exactAllowed = false;
      exactRequestGranted = false;
      await service.sync(dashboard());
      calls.clear();
      expect(await service.enable(), isNull);
      expect(service.limitation, contains('atrasar'));
      final scheduled = calls.where((call) => call.method == 'zonedSchedule');
      expect(scheduled, isNotEmpty);
      expect(
        scheduled.every(
          (call) =>
              (call.arguments as Map)['platformSpecifics']['scheduleMode'] ==
              'inexactAllowWhileIdle',
        ),
        isTrue,
      );
    },
  );

  test(
    'notification test displays immediately and reports native errors',
    () async {
      expect(await service.testNotification(), contains('Ative'));
      expect(calls.where((call) => call.method == 'show'), isEmpty);
      await service.enable();
      expect(await service.testNotification(), isNull);
      expect(calls.last.method, 'show');
      expect((calls.last.arguments as Map)['id'], 0);
      showFails = true;
      expect(await service.testNotification(), contains('Não foi possível'));
    },
  );

  test('permission revocation is detected even after activation', () async {
    await service.sync(dashboard());
    expect(service.enabled, isTrue);
    calls.clear();
    notificationsAllowed = false;
    await service.sync(dashboard());
    expect(service.enabled, isFalse);
    expect(service.error, contains('bloqueadas'));
    expect(
      calls.any((call) => call.method == 'cancelAllPendingNotifications'),
      isTrue,
    );
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
  });

  testWidgets('activation offers an immediate notification test', (
    tester,
  ) async {
    try {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(
            dashboardFixture([
              {
                ...habitFixture(),
                'completed_today': false,
                'reminder_time': '23:59',
              },
            ]),
          ),
          200,
        ),
      );
      final repository = HabitRepository('http://localhost', client: client);
      addTearDown(client.close);
      await tester.pumpWidget(
        HabitQuest(baseUrl: 'http://localhost', repository: repository),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ativar lembretes'));
      await tester.pumpAndSettle();
      expect(find.text('Testar notificação'), findsOneWidget);
      await tester.tap(find.text('Testar notificação'));
      await tester.pumpAndSettle();
      expect(calls.any((call) => call.method == 'show'), isTrue);
      expect(find.textContaining('Teste enviado ao sistema.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
