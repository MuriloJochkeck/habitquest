import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest/habits_bloc.dart';
import 'package:habitquest/habits_data.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

void main() {
  test('duplo toque pendente envia um PUT e confirma XP uma vez', () async {
    final response = Completer<http.Response>();
    var puts = 0;
    final client = MockClient((request) async {
      if (request.method == 'PUT') {
        puts++;
        expect(request.headers['x-habit-date'], '2026-11-19');
        return response.future;
      }
      return http.Response(jsonEncode(dashboardFixture()), 200);
    });
    addTearDown(client.close);
    final bloc = HabitsBloc(
      HabitRepository('http://localhost', client: client),
    );
    addTearDown(bloc.close);
    await bloc.add(const HabitsRequested());
    final first = bloc.add(const HabitCheckInRequested(1));
    await bloc.add(const HabitCheckInRequested(1));
    expect(bloc.state.pendingId, 1);
    response.complete(http.Response('{"awarded_xp":60}', 201));
    await first;
    expect(puts, 1);
    expect(bloc.state.reward, 60);
  });

  test('falha ao atualizar preserva dados confirmados', () async {
    var calls = 0;
    final client = MockClient(
      (_) async => ++calls == 1
          ? http.Response(jsonEncode(dashboardFixture()), 200)
          : http.Response('', 503),
    );
    addTearDown(client.close);
    final bloc = HabitsBloc(
      HabitRepository('http://localhost', client: client),
    );
    addTearDown(bloc.close);
    await bloc.add(const HabitsRequested());
    final previous = bloc.state.dashboard;
    await bloc.add(const HabitsRequested());
    expect(bloc.state.dashboard, same(previous));
    expect(bloc.state.error, isNotNull);
    expect(bloc.state.busy, isFalse);
  });

  test('virada do dia atualiza data sem repetir realização', () async {
    var puts = 0;
    var gets = 0;
    final client = MockClient((request) async {
      if (request.method == 'PUT') {
        puts++;
        return http.Response(
          '{"error":{"code":"day_changed","message":"Atualize a data."}}',
          409,
        );
      }
      gets++;
      return http.Response(
        jsonEncode({
          ...dashboardFixture(),
          'local_date': gets > 1 ? '2026-11-20' : '2026-11-19',
        }),
        200,
      );
    });
    addTearDown(client.close);
    final bloc = HabitsBloc(
      HabitRepository('http://localhost', client: client),
    );
    addTearDown(bloc.close);
    await bloc.add(const HabitsRequested());
    final refreshed = bloc.states.firstWhere(
      (s) => s.dashboard?.date == '2026-11-20' && !s.busy,
    );
    await bloc.add(const HabitCheckInRequested(1));
    await refreshed;
    expect(puts, 1);
    expect(gets, 2);
  });
}
