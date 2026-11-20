import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests do not run Flutter's generated native plugin registrant.
/// Register the real Dart implementation and simulate a device on which the
/// user has not enabled notifications. Permission and alarm scheduling remain
/// covered by device verification, not by simulated platform responses.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => switch (call.method) {
          'initialize' => true,
          'areNotificationsEnabled' => false,
          'requestNotificationsPermission' => false,
          'cancelAllPendingNotifications' => null,
          _ => throw UnsupportedError(
            'Unexpected notification method: ${call.method}',
          ),
        },
      );
  await testMain();
}
