import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class Habit {
  Habit.fromJson(Json data)
    : id = data['id'] as int,
      name = data['name'] as String,
      description = data['description'] as String,
      icon = data['icon'] as String,
      color = data['color'] as String,
      target = data['weekly_target'] as int,
      count = data['weekly_count'] as int,
      streak = data['streak'] as int,
      adherence = (data['adherence'] as num?)?.toDouble(),
      completed = data['completed_today'] as bool,
      scheduledDays = List<int>.from(data['scheduled_days'] as List? ?? []),
      reminderTime = data['reminder_time'] as String?,
      dailyTarget = data['daily_target'] as int? ?? 1,
      unit = data['unit'] as String? ?? 'vez',
      todayQuantity =
          data['today_quantity'] as int? ??
          (data['completed_today'] == true ? 1 : 0),
      scheduledToday = data['scheduled_today'] as bool? ?? true,
      archived = data['archived_at'] != null,
      weeklyHistory = (data['weekly_history'] as List? ?? [])
          .cast<Json>()
          .map(WeeklyProgress.fromJson)
          .toList(),
      weekDays = List<String>.from(data['week_days'] as List);

  final int id, target, count, streak;
  final String name, description, icon, color;
  final bool completed, archived;
  final List<int> scheduledDays;
  final String? reminderTime;
  final int dailyTarget, todayQuantity;
  final String unit;
  final bool scheduledToday;
  final double? adherence;
  final List<String> weekDays;
  final List<WeeklyProgress> weeklyHistory;
}

class WeeklyProgress {
  WeeklyProgress.fromJson(Json data)
    : start = data['week_start'] as String,
      count = data['weekly_count'] as int,
      target = data['weekly_target'] as int,
      complete = data['complete_week'] as bool;
  final String start;
  final int count, target;
  final bool complete;
}

class Achievement {
  Achievement.fromJson(Json data)
    : habit = data['habit_name'] as String,
      title = data['title'] as String,
      code = data['code'] as String,
      requirement = data['requirement'] as String?,
      unlocked = data['unlocked_at'] != null;

  final String habit, title, code;
  final bool unlocked;
  final String? requirement;
}

class Dashboard {
  Dashboard.fromJson(Json data)
    : date = data['local_date'] as String,
      weekStart = DateTime.parse(data['week_start'] as String),
      xp = data['total_xp'] as int,
      level = data['level'] as int,
      avatar = data['avatar'] as String? ?? 'compass',
      weeklySummary = data['weekly_summary'] == null
          ? null
          : WeeklySummary.fromJson(data['weekly_summary'] as Json),
      habits = (data['habits'] as List)
          .cast<Json>()
          .map(Habit.fromJson)
          .toList(),
      achievements = (data['achievements'] as List)
          .cast<Json>()
          .map(Achievement.fromJson)
          .toList();

  final String date;
  final DateTime weekStart;
  final int xp, level;
  final String avatar;
  final WeeklySummary? weeklySummary;
  final List<Habit> habits;
  final List<Achievement> achievements;
}

class WeeklySummary {
  WeeklySummary.fromJson(Json data)
    : current = data['current_count'] as int,
      previous = data['previous_count'] as int,
      delta = data['delta'] as int,
      currentStart = data['current_start'] as String,
      currentEnd = data['current_end'] as String,
      previousStart = data['previous_start'] as String,
      previousEnd = data['previous_end'] as String,
      bestHabit = data['best_habit_name'] as String?;
  final int current, previous, delta;
  final String currentStart, currentEnd, previousStart, previousEnd;
  final String? bestHabit;
}

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.code, this.outcomeUnknown = false});
  final String message;
  final String? code;
  final bool outcomeUnknown;
}

class HabitRepository {
  HabitRepository(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  Future<T> _request<T>(
    String method,
    String path,
    T Function(Object?) decode, {
    Json? body,
    String? date,
  }) async {
    final uncertainCreation = method == 'POST' && path == '/habits';
    final request = http.Request(method, Uri.parse('$baseUrl/api/v1$path'));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }
    if (date != null) request.headers['X-Habit-Date'] = date;
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 500) {
        throw ApiFailure(
          'O serviço está indisponível. Tente novamente.',
          outcomeUnknown: uncertainCreation,
        );
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = (data as Json)['error'] as Json;
        final fields = error['fields'] as Json?;
        throw ApiFailure(
          fields?.values.firstOrNull as String? ?? error['message'] as String,
          code: error['code'] as String,
        );
      }
      return decode(data);
    } on TimeoutException {
      throw ApiFailure(
        'A API demorou para responder. Confira os dados antes de repetir.',
        outcomeUnknown: uncertainCreation,
      );
    } on http.ClientException {
      throw ApiFailure(
        'Sem conexão com a API. Confira a rede e tente novamente.',
        outcomeUnknown: uncertainCreation,
      );
    } on FormatException {
      throw ApiFailure(
        'A API enviou uma resposta inválida.',
        outcomeUnknown: uncertainCreation,
      );
    } on TypeError {
      throw ApiFailure(
        'A API enviou dados em formato inesperado.',
        outcomeUnknown: uncertainCreation,
      );
    }
  }

  Future<Dashboard> dashboard() =>
      _request('GET', '/dashboard', (data) => Dashboard.fromJson(data as Json));

  Future<List<Habit>> archived() => _request(
    'GET',
    '/habits?status=archived',
    (data) => (data as List).cast<Json>().map(Habit.fromJson).toList(),
  );

  Future<Habit> detail(int id) =>
      _request('GET', '/habits/$id', (data) => Habit.fromJson(data as Json));

  Future<List<String>> history(int id, String from, String to) => _request(
    'GET',
    '/habits/$id/checkins?from=$from&to=$to',
    (data) => (data as List)
        .cast<Json>()
        .map((row) => row['local_date'] as String)
        .toList(),
  );

  Future<void> save(Json fields, {int? id}) => _request(
    id == null ? 'POST' : 'PATCH',
    id == null ? '/habits' : '/habits/$id',
    (_) {},
    body: fields,
  );

  Future<void> archive(int id) =>
      _request('POST', '/habits/$id/archive', (_) {});

  Future<int> checkInToday(int id, String date, {int? quantity}) => _request(
    'PUT',
    '/habits/$id/checkins/today',
    (data) => (data as Json)['awarded_xp'] as int,
    date: date,
    body: quantity == null ? null : {'quantity': quantity},
  );

  Future<void> undoToday(int id, String date) =>
      _request('DELETE', '/habits/$id/checkins/today', (_) {}, date: date);

  Future<void> selectAvatar(String avatar) =>
      _request('PATCH', '/profile', (_) {}, body: {'avatar': avatar});

  void close() {
    if (_ownsClient) _client.close();
  }
}
