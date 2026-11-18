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
      archived = data['archived_at'] != null,
      weekDays = List<String>.from(data['week_days'] as List);

  final int id, target, count, streak;
  final String name, description, icon, color;
  final bool completed, archived;
  final double? adherence;
  final List<String> weekDays;
}

class Achievement {
  Achievement.fromJson(Json data)
    : habit = data['habit_name'] as String,
      title = data['title'] as String,
      code = data['code'] as String,
      unlocked = data['unlocked_at'] != null;

  final String habit, title, code;
  final bool unlocked;
}

class Dashboard {
  Dashboard.fromJson(Json data)
    : date = data['local_date'] as String,
      weekStart = DateTime.parse(data['week_start'] as String),
      xp = data['total_xp'] as int,
      level = data['level'] as int,
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
  final List<Habit> habits;
  final List<Achievement> achievements;
}

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.code});
  final String message;
  final String? code;
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
        throw const ApiFailure('O serviço está indisponível. Tente novamente.');
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
      throw const ApiFailure(
        'A API demorou para responder. Confira os dados antes de repetir.',
      );
    } on http.ClientException {
      throw const ApiFailure(
        'Sem conexão com a API. Confira a rede e tente novamente.',
      );
    } on FormatException {
      throw const ApiFailure('A API enviou uma resposta inválida.');
    } on TypeError {
      throw const ApiFailure('A API enviou dados em formato inesperado.');
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

  Future<int> checkInToday(int id, String date) => _request(
    'PUT',
    '/habits/$id/checkins/today',
    (data) => (data as Json)['awarded_xp'] as int,
    date: date,
  );

  void close() {
    if (_ownsClient) _client.close();
  }
}
