import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest/habits_data.dart';
import 'package:habitquest/reminders.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import 'fixtures.dart';

void main() {
  late tz.Location zone;
  setUpAll(() {
    timezone_data.initializeTimeZones();
    zone = tz.getLocation('America/Sao_Paulo');
  });

  Dashboard dashboard(Map<String, dynamic> overrides) => Dashboard.fromJson(
    dashboardFixture([
      {...habitFixture(), 'completed_today': false, ...overrides},
    ]),
  );

  test('scheduled weekdays and Sao Paulo time determine future deliveries', () {
    final result = planReminders(
      dashboard({
        'reminder_time': '20:30',
        'scheduled_days': [1, 3, 5],
      }),
      tz.TZDateTime(zone, 2026, 11, 19, 21), // Thursday
      days: 7,
    );
    expect(result.map((item) => item.at.weekday), [5, 1, 3]);
    expect(
      result.every((item) => item.at.hour == 20 && item.at.minute == 30),
      isTrue,
    );
    expect(result.first.at.timeZoneOffset, const Duration(hours: -3));
  });

  test(
    'completion suppresses only today, preserving tomorrow and later days',
    () {
      final result = planReminders(
        dashboard({'reminder_time': '20:30', 'completed_today': true}),
        tz.TZDateTime(zone, 2026, 11, 19, 10),
        days: 30,
      );
      expect(result.length, 29);
      expect(result.first.at.day, 20);
    },
  );

  test('disabled, archived and invalid reminders never deliver', () {
    final now = tz.TZDateTime(zone, 2026, 11, 19, 10);
    for (final fields in [
      <String, dynamic>{'reminder_time': null},
      {'reminder_time': '25:00'},
      {'reminder_time': '20:30', 'archived_at': '2026-11-19T12:00:00+00:00'},
    ]) {
      expect(planReminders(dashboard(fields), now), isEmpty);
    }
  });

  test('past times are not replayed; flexible habits get daily reminders', () {
    final result = planReminders(
      dashboard({'reminder_time': '09:00', 'scheduled_days': []}),
      tz.TZDateTime(zone, 2026, 11, 19, 10),
      days: 3,
    );
    expect(result.map((item) => item.at.day), [20, 21]);
  });

  test('month and year rollover preserve the selected weekday', () {
    final result = planReminders(
      dashboard({
        'reminder_time': '07:00',
        'scheduled_days': [5],
      }),
      tz.TZDateTime(zone, 2026, 12, 31, 10),
      days: 3,
    );
    expect(result.single.at.year, 2027);
    expect(result.single.at.month, 1);
    expect(result.single.at.day, 1);
  });
}
