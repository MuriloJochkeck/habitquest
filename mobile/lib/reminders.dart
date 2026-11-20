import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import 'habits_data.dart';

/// A concrete future delivery, independent of the platform notification API.
class ReminderDelivery {
  const ReminderDelivery(this.habitId, this.name, this.at);
  final int habitId;
  final String name;
  final tz.TZDateTime at;
}

/// Dates use the profile's zone, never the device's local calendar.
List<ReminderDelivery> planReminders(
  Dashboard dashboard,
  tz.TZDateTime now, {
  int days = 30,
}) {
  final result = <ReminderDelivery>[];
  for (final habit in dashboard.habits) {
    final time = habit.reminderTime;
    if (time == null || habit.archived) continue;
    final parts = time.split(':');
    if (parts.length != 2) continue;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      continue;
    }
    for (var offset = 0; offset < days; offset++) {
      final at = tz.TZDateTime(
        now.location,
        now.year,
        now.month,
        now.day + offset,
        hour,
        minute,
      );
      final date =
          '${at.year.toString().padLeft(4, '0')}-'
          '${at.month.toString().padLeft(2, '0')}-'
          '${at.day.toString().padLeft(2, '0')}';
      if (!at.isAfter(now) ||
          (habit.scheduledDays.isNotEmpty &&
              !habit.scheduledDays.contains(at.weekday)) ||
          (date == dashboard.date && habit.completed)) {
        continue;
      }
      result.add(ReminderDelivery(habit.id, habit.name, at));
    }
  }
  result.sort((a, b) => a.at.compareTo(b.at));
  return result;
}

/// OS scheduling on Android; foreground delivery on Windows and Web.
/// No permission prompts occur from sync().
class ReminderService {
  ReminderService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Timer? _timer;
  bool _initialized = false;
  bool _enabled = false;
  bool _closed = false;
  Future<void> _pending = Future.value();
  Dashboard? _dashboard;
  final Set<String> _delivered = {};
  String? error;

  bool get enabled => _enabled;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _supported =>
      kIsWeb || _android || defaultTargetPlatform == TargetPlatform.windows;
  String get limitation => _android
      ? 'Horário de São Paulo. Lembretes agendados para os próximos 30 dias; '
            'abra o app para renovar. O Android pode atrasar a entrega para economizar bateria.'
      : 'Horário de São Paulo. Mantenha ${kIsWeb ? 'esta aba aberta' : 'o app aberto'} '
            'para receber lembretes. Ative as notificações neste dispositivo.';

  Future<bool> _initialize() async {
    if (_initialized) return true;
    if (!_supported || _closed) return false;
    timezone_data.initializeTimeZones();
    _initialized =
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification'),
            windows: WindowsInitializationSettings(
              appName: 'HabitQuest',
              appUserModelId: 'HabitQuest.App.Desktop',
              guid: '7cb7647d-10b1-4d69-ae86-794b5a7e537a',
            ),
            web: WebInitializationSettings(),
          ),
        ) ??
        false;
    return _initialized;
  }

  /// Call only from an explicit user action (especially for browsers).
  Future<String?> enable() async {
    if (!_supported) return error = 'Lembretes indisponíveis nesta plataforma.';
    if (_closed) return error = 'Reabra o aplicativo para ativar lembretes.';
    try {
      // Request Web permission before any asynchronous initialization so the
      // browser retains the initiating user gesture.
      if (kIsWeb) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
              WebFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        if (granted != true) {
          return error =
              'Notificações bloqueadas. Permita-as nas configurações do navegador.';
        }
      }
      if (!await _initialize()) {
        return error =
            'Não foi possível iniciar as notificações neste dispositivo.';
      }
      if (_android) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        if (granted != true) {
          return error =
              'Notificações bloqueadas. Permita-as nas configurações do Android.';
        }
      }
      if (_closed) return null;
      _enabled = true;
      error = null;
      final dashboard = _dashboard;
      if (dashboard != null) await sync(dashboard);
      return error;
    } on PlatformException {
      return error =
          'Não foi possível ativar as notificações. Confira as permissões do sistema.';
    } on MissingPluginException {
      return error =
          'Reinicie o aplicativo após instalar a atualização de lembretes.';
    } on UnsupportedError {
      return error = 'Este ambiente não oferece suporte a notificações.';
    } on StateError {
      return error =
          'Não foi possível iniciar as notificações. Ative-as novamente.';
    }
  }

  /// Serialized reconciliation prevents older dashboard states replacing newer
  /// schedules when HTTP refreshes arrive while native calls are in flight.
  Future<void> sync(Dashboard dashboard) {
    _dashboard = dashboard;
    _pending = _pending.then((_) => _sync(dashboard));
    return _pending;
  }

  Future<void> _sync(Dashboard dashboard) async {
    if (_closed) return;
    try {
      if (!_enabled && _android) {
        if (!await _initialize()) return;
        _enabled =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.areNotificationsEnabled() ??
            false;
        // Cancel stale native deliveries even when permission was revoked.
        if (!_enabled) await _plugin.cancelAllPendingNotifications();
      }
      if (!_enabled || _closed) return;
      error = null;
      final now = tz.TZDateTime.now(tz.getLocation('America/Sao_Paulo'));
      if (_android) {
        final deliveries = planReminders(dashboard, now);
        await _plugin.cancelAllPendingNotifications();
        if (deliveries.length > 400) {
          error = 'Limite de lembretes atingido. Reduza os hábitos com lembrete e ative novamente.';
          return;
        }
        for (var i = 0; i < deliveries.length && !_closed; i++) {
          final delivery = deliveries[i];
          await _plugin.zonedSchedule(
            id: i + 1,
            title: 'Hora da sua missão',
            body: delivery.name,
            scheduledDate: delivery.at,
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      } else {
        _timer?.cancel();
        // Poll only for foreground platforms; OS/browser may throttle while
        // asleep. Never send a burst of missed reminders on resuming.
        _timer = Timer.periodic(const Duration(seconds: 20), (_) {
          unawaited(_deliverForeground());
        });
      }
    } on PlatformException {
      error = 'Não foi possível atualizar os lembretes. Confira as permissões e ative novamente.';
    } on MissingPluginException {
      error = 'Reinicie o aplicativo para carregar o serviço de lembretes.';
    } on UnsupportedError {
      error = 'Este ambiente não oferece suporte a lembretes.';
    } on StateError {
      error =
          'Notificações indisponíveis. Ative-as novamente neste dispositivo.';
    }
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'habitquest_reminders',
      'Lembretes de hábitos',
      channelDescription: 'Horários escolhidos para suas missões',
    ),
    windows: WindowsNotificationDetails(),
  );

  Future<void> _deliverForeground() async {
    final dashboard = _dashboard;
    if (!_enabled || _closed || dashboard == null) return;
    final now = tz.TZDateTime.now(tz.getLocation('America/Sao_Paulo'));
    final minuteStart = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final candidates = planReminders(
      dashboard,
      minuteStart.subtract(const Duration(microseconds: 1)),
      days: 1,
    );
    for (final delivery in candidates) {
      if (delivery.at != minuteStart) continue;
      final key = '${delivery.habitId}:${delivery.at.toIso8601String()}';
      if (!_delivered.add(key)) continue;
      try {
        await _plugin.show(
          id: delivery.habitId % 2147483647,
          title: 'Hora da sua missão',
          body: delivery.name,
          notificationDetails: _details,
        );
      } on PlatformException {
        error = 'Não foi possível exibir o lembrete. Confira as permissões.';
      } on StateError {
        error =
            'Notificações indisponíveis. Ative-as novamente neste dispositivo.';
      }
    }
    // Keep only a small recent history during long running desktop sessions.
    if (_delivered.length > 1000) _delivered.remove(_delivered.first);
  }

  void close() {
    _closed = true;
    _timer?.cancel();
  }
}
