import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest/habits_data.dart';
import 'package:habitquest/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

Future<void> reveal(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label).hitTestable(),
    140,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('quantidade parcial, conclusão e desfazer preservam o contrato', (
    tester,
  ) async {
    final habit = habitFixture()
      ..addAll({
        'daily_target': 20,
        'unit': 'minutos',
        'today_quantity': 0,
        'completed_today': false,
        'weekly_count': 0,
        'week_days': <String>[],
      });
    var xp = 0;
    final mutations = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'PUT') {
        final quantity = (jsonDecode(request.body) as Json)['quantity'] as int;
        mutations.add('PUT:$quantity');
        habit['today_quantity'] = quantity;
        habit['completed_today'] = quantity >= 20;
        xp = quantity >= 20 ? 10 : 0;
        return http.Response(jsonEncode({'awarded_xp': xp}), 200);
      }
      if (request.method == 'DELETE') {
        expect(request.headers['x-habit-date'], '2026-11-19');
        mutations.add('DELETE');
        habit['today_quantity'] = 0;
        habit['completed_today'] = false;
        xp = 0;
        return http.Response('{}', 200);
      }
      return http.Response(
        jsonEncode({
          ...dashboardFixture([habit]),
          'total_xp': xp,
        }),
        200,
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      HabitQuest(
        baseUrl: 'http://localhost',
        repository: HabitRepository('http://localhost', client: client),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> setQuantity(String amount) async {
      await reveal(tester, 'Registrar quantidade');
      await tester.tap(find.text('Registrar quantidade'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), amount);
      await tester.tap(find.text('Salvar progresso'));
      await tester.pumpAndSettle();
    }

    await setQuantity('10');
    expect(find.text('10 de 20 minutos hoje'), findsOneWidget);
    expect(xp, 0);
    await tester.pump(const Duration(seconds: 5));
    await setQuantity('20');
    expect(find.text('Concluído hoje'), findsOneWidget);
    expect(xp, 10);
    await tester.pump(const Duration(seconds: 5));
    await reveal(tester, 'Desfazer registro de hoje');
    await tester.tap(find.text('Desfazer registro de hoje'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect(find.text('0 de 20 minutos hoje'), findsOneWidget);
    expect(xp, 0);
    expect(mutations, ['PUT:10', 'PUT:20', 'DELETE']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('separa dias programados, mostra resumo e persiste avatar', (
    tester,
  ) async {
    var avatar = 'compass';
    final habit = habitFixture()
      ..addAll({
        'scheduled_today': false,
        'scheduled_days': [1, 3, 5],
      });
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        expect(request.url.path, '/api/v1/profile');
        avatar = (jsonDecode(request.body) as Json)['avatar'] as String;
        return http.Response('{}', 200);
      }
      return http.Response(
        jsonEncode({
          ...dashboardFixture([habit]),
          'avatar': avatar,
          'weekly_summary': {
            'current_count': 4,
            'previous_count': 2,
            'delta': 2,
            'current_start': '2026-11-16',
            'current_end': '2026-11-19',
            'previous_start': '2026-11-09',
            'previous_end': '2026-11-12',
            'best_habit_name': 'Leitura',
          },
        }),
        200,
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      HabitQuest(
        baseUrl: 'http://localhost',
        repository: HabitRepository('http://localhost', client: client),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 de 0 missões feitas hoje'), findsOneWidget);
    expect(find.textContaining('Nenhuma missão programada'), findsOneWidget);
    await reveal(tester, 'Outros dias da sua rotina');
    await tester.tap(find.text('Progresso'));
    await tester.pumpAndSettle();
    await reveal(tester, 'Sua semana em perspectiva');
    expect(find.textContaining('+2 em relação'), findsOneWidget);
    await tester.tap(find.text('Conquistas'));
    await tester.pumpAndSettle();
    await reveal(tester, 'Guardião');
    await tester.tap(find.text('Guardião'));
    await tester.pumpAndSettle();
    expect(avatar, 'leaf');
    expect(tester.takeException(), isNull);
  });
}
