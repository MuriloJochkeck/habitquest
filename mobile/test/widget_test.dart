import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest/habits_data.dart';
import 'package:habitquest/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('cria um hábito, conclui a meta e mostra recompensa', (
    tester,
  ) async {
    Json? habit;
    var xp = 0;
    var checkins = 0;
    final client = MockClient((request) async {
      final path = request.url.path;
      Object? response;
      var status = 200;
      if (path.endsWith('/dashboard')) {
        response = {
          'local_date': '2026-11-16',
          'week_start': '2026-11-16',
          'total_xp': xp,
          'level': 1,
          'achievements': [],
          'habits': [?habit],
        };
      } else if (request.method == 'POST' && path.endsWith('/habits')) {
        final body = jsonDecode(request.body) as Json;
        habit = {
          ...body,
          'id': 1,
          'weekly_count': 0,
          'streak': 0,
          'completed_today': false,
          'week_days': [],
        };
        response = habit;
        status = 201;
      } else if (request.method == 'PUT' &&
          path.endsWith('/1/checkins/today')) {
        expect(request.headers['x-habit-date'], '2026-11-16');
        checkins++;
        xp = 60;
        habit!.addAll({
          'weekly_count': 1,
          'streak': 1,
          'completed_today': true,
          'week_days': ['2026-11-16'],
        });
        response = {'awarded_xp': 60};
        status = 201;
      } else {
        fail('Rota inesperada: ${request.method} $path');
      }
      return http.Response(
        jsonEncode(response),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final repository = HabitRepository('http://localhost:5000', client: client);
    await tester.pumpWidget(
      HabitQuest(baseUrl: 'http://localhost:5000', repository: repository),
    );
    await tester.pumpAndSettle();
    expect(find.text('Crie seu primeiro hábito para começar.'), findsOneWidget);

    await tester.tap(find.text('Novo hábito'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Leitura');
    await tester.tap(find.text('3 dia(s)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 dia(s)').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Salvar hábito'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Salvar hábito'));
    await tester.pumpAndSettle();
    expect(find.text('Leitura'), findsOneWidget);
    expect(habit!['weekly_target'], 1);

    await tester.scrollUntilVisible(
      find.text('Concluir hoje').hitTestable(),
      75,
    );
    await tester.tap(find.text('Concluir hoje'));
    await tester.pumpAndSettle();
    expect(find.text('Concluído hoje'), findsOneWidget);
    expect(find.textContaining('60 XP no total'), findsOneWidget);
    expect(checkins, 1);
  });

  testWidgets('mostra falha de rede e permite tentar novamente', (
    tester,
  ) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) return http.Response('', 503);
      return http.Response(
        '{"local_date":"2026-11-16","week_start":"2026-11-16","habits":[],"achievements":[],"total_xp":0,"level":1}',
        200,
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      HabitQuest(
        baseUrl: 'http://localhost:5000',
        repository: HabitRepository('http://localhost:5000', client: client),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Novo hábito'), findsOneWidget);
    expect(calls, 2);
  });
}
