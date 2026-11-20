import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest/habit_pages.dart';
import 'package:habitquest/habits_bloc.dart';
import 'package:habitquest/habits_data.dart';
import 'package:habitquest/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target.hitTestable(),
    150,
    scrollable: find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cadastro sem confirmação exige conferir lista antes de novo envio',
    (tester) async {
      var posts = 0;
      var dashboardCalls = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          return http.Response('', 503);
        }
        dashboardCalls++;
        return http.Response(jsonEncode(dashboardFixture([])), 200);
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        HabitQuest(
          baseUrl: 'http://localhost',
          repository: HabitRepository('http://localhost', client: client),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novo hábito'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Leitura');
      await reveal(tester, find.text('Salvar hábito'));
      await tester.tap(find.text('Salvar hábito'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Salvar hábito'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Salvar hábito'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Confira na lista'), findsOneWidget);
      await reveal(tester, find.text('Conferir lista de hábitos'));
      await tester.tap(find.text('Conferir lista de hábitos'));
      await tester.pumpAndSettle();
      expect(find.text('Missões de hoje'), findsOneWidget);
      expect(posts, 1);
      expect(dashboardCalls, 2);
    },
  );

  testWidgets(
    'edita sem alterar meta e arquiva preservando acesso ao histórico',
    (tester) async {
      final habit = habitFixture();
      Json? patched;
      final client = MockClient((request) async {
        if (request.method == 'PATCH') {
          patched = jsonDecode(request.body) as Json;
          habit.addAll(patched!);
        } else if (request.url.path.endsWith('/archive')) {
          habit['archived_at'] = '2026-11-19T12:00:00Z';
        }
        final Object result;
        if (request.url.path.endsWith('/dashboard')) {
          result = dashboardFixture(
            habit['archived_at'] == null ? [habit] : [],
          );
        } else if (request.url.queryParameters['status'] == 'archived') {
          result = [habit];
        } else if (request.url.path.endsWith('/checkins')) {
          result = [
            {'local_date': '2026-11-19'},
          ];
        } else {
          result = habit;
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
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
      await tester.ensureVisible(find.text('Leitura'));
      await tester.tap(find.text('Leitura'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Editar hábito'));
      await tester.tap(find.text('Editar hábito'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.byType(DropdownButtonFormField<int>),
            )
            .onChanged,
        isNull,
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'Leitura diária',
      );
      await reveal(tester, find.text('Salvar hábito'));
      await tester.tap(find.text('Salvar hábito'));
      await tester.pumpAndSettle();
      expect(patched!['name'], 'Leitura diária');
      expect(patched!.containsKey('weekly_target'), isFalse);
      expect(find.text('Leitura diária'), findsOneWidget);
      // Aguarda a duração da confirmação antes de usar o botão sob a SnackBar.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Arquivar hábito'));
      await tester.tap(find.text('Arquivar hábito'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arquivar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Crie seu primeiro hábito para começar.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Progresso'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Hábitos arquivados'));
      await tester.tap(find.text('Hábitos arquivados'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leitura diária'));
      await tester.pumpAndSettle();
      expect(find.text('1 realização(ões) no mês'), findsOneWidget);
      expect(find.text('Editar hábito'), findsNothing);
      expect(find.text('Arquivar hábito'), findsNothing);
    },
  );

  testWidgets(
    'calendário em 320 pixels e fonte 2x mantém dias legíveis e histórico',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('/checkins')
                ? [
                    {'local_date': '2026-11-19'},
                  ]
                : habitFixture(),
          ),
          200,
        ),
      );
      addTearDown(client.close);
      final bloc = HabitsBloc(
        HabitRepository('http://localhost', client: client),
      );
      addTearDown(bloc.close);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: HabitDetail(
            bloc: bloc,
            habit: Habit.fromJson(habitFixture()),
            date: '2026-11-19',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await reveal(tester, find.text('19'));
      final daySize = tester.getSize(find.text('19'));
      expect(daySize.height, greaterThanOrEqualTo(24));
      expect(
        tester.widget<Text>(find.text('19')).style?.decoration,
        TextDecoration.underline,
      );
      expect(
        tester.widget<Text>(find.text('20')).style?.decoration,
        isNot(TextDecoration.underline),
      );
      await tester.scrollUntilVisible(
        find.text('Frequência por semana'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Semana de 09/11/2026: 0 de 3 dias'),
        findsOneWidget,
      );
      expect(
        find.textContaining('4 de 3 dias · semana parcial'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
