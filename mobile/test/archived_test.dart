import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest/habits_data.dart';
import 'package:habitquest/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

Future<void> openArchived(
  WidgetTester tester,
  HabitRepository repository,
) async {
  await tester.pumpWidget(
    HabitQuest(baseUrl: 'http://localhost', repository: repository),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Progresso'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Hábitos arquivados').hitTestable(),
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Hábitos arquivados'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Leitura'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'desarquiva, recupera após falha e atualiza lista sem perder XP',
    (tester) async {
      final habit = habitFixture()..['archived_at'] = '2026-11-19T12:00:00Z';
      var restores = 0;
      var dashboardCalls = 0;
      final client = MockClient((request) async {
        Object result;
        if (request.url.path.endsWith('/restore')) {
          restores++;
          expect(request.method, 'POST');
          if (restores == 1) return http.Response('', 503);
          habit['archived_at'] = null;
          result = habit;
        } else if (request.url.path.endsWith('/dashboard')) {
          dashboardCalls++;
          result = dashboardFixture(
            habit['archived_at'] == null ? [habit] : [],
          );
        } else if (request.url.queryParameters['status'] == 'archived') {
          result = habit['archived_at'] == null ? [] : [habit];
        } else if (request.url.path.endsWith('/checkins')) {
          result = [
            {'local_date': '2026-11-19'},
          ];
        } else {
          result = habit;
        }
        return http.Response(jsonEncode(result), 200);
      });
      addTearDown(client.close);
      await openArchived(
        tester,
        HabitRepository('http://localhost', client: client),
      );
      expect(find.text('Desarquivar hábito'), findsOneWidget);
      expect(find.text('Excluir permanentemente'), findsOneWidget);
      await tester.tap(find.text('Desarquivar hábito'));
      await tester.pumpAndSettle();
      expect(find.textContaining('serviço está indisponível'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Desarquivar hábito'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text('Desarquivar hábito'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum hábito arquivado.'), findsOneWidget);
      expect(habit['weekly_count'], 4);
      expect(restores, 2);
      expect(dashboardCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'exclusão exige confirmação, remove da lista e atualiza dashboard',
    (tester) async {
      final habit = habitFixture()..['archived_at'] = '2026-11-19T12:00:00Z';
      var deleted = false;
      var deletes = 0;
      var refreshedXp = 90;
      final client = MockClient((request) async {
        Object result;
        if (request.method == 'DELETE') {
          expect(request.url.path, '/api/v1/habits/1');
          deletes++;
          deleted = true;
          result = {'deleted': true, 'id': 1};
        } else if (request.url.path.endsWith('/dashboard')) {
          refreshedXp = deleted ? 0 : 90;
          result = {...dashboardFixture([]), 'total_xp': refreshedXp};
        } else if (request.url.queryParameters['status'] == 'archived') {
          result = deleted ? [] : [habit];
        } else if (request.url.path.endsWith('/checkins')) {
          result = [
            {'local_date': '2026-11-19'},
          ];
        } else {
          result = habit;
        }
        return http.Response(jsonEncode(result), 200);
      });
      addTearDown(client.close);
      await openArchived(
        tester,
        HabitRepository('http://localhost', client: client),
      );
      await tester.tap(find.text('Excluir permanentemente'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Esta ação não pode ser desfeita'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(deletes, 0);
      expect(find.text('Desarquivar hábito'), findsOneWidget);
      await tester.tap(find.text('Excluir permanentemente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir tudo'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(refreshedXp, 0);
      expect(find.text('Nenhum hábito arquivado.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
