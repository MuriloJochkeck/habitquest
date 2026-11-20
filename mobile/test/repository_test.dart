import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest/habits_data.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

void main() {
  test('confirma exclusão após perder resposta sem repetir DELETE', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add(request.method);
      if (request.method == 'DELETE') {
        throw http.ClientException('Resposta perdida');
      }
      return http.Response(
        '{"error":{"code":"not_found","message":"Hábito não encontrado."}}',
        404,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    await HabitRepository('http://localhost', client: client).delete(1);
    expect(calls, ['DELETE', 'GET']);
  });

  test(
    'confirma desarquivamento após perder resposta sem repetir POST',
    () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add(request.method);
        if (request.method == 'POST') {
          throw http.ClientException('Resposta perdida');
        }
        return http.Response(jsonEncode(habitFixture()), 200);
      });
      addTearDown(client.close);
      await HabitRepository('http://localhost', client: client).restore(1);
      expect(calls, ['POST', 'GET']);
    },
  );

  test(
    'decodifica frequência zero, contagem acima da meta e semana parcial',
    () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(dashboardFixture()), 200),
      );
      addTearDown(client.close);
      final dashboard = await HabitRepository(
        'http://localhost',
        client: client,
      ).dashboard();
      final history = dashboard.habits.single.weeklyHistory;
      expect(history.first.count, 0);
      expect(history.first.complete, isTrue);
      expect(history.last.count, 4);
      expect(history.last.target, 3);
      expect(history.last.complete, isFalse);
    },
  );

  for (final failure in ['timeout', 'network', 'server', 'invalid']) {
    test(
      'cadastro com $failure informa confirmação desconhecida sem repetir POST',
      () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return switch (failure) {
            'timeout' => throw TimeoutException('resposta perdida'),
            'network' => throw http.ClientException('conexão perdida'),
            'server' => http.Response('', 503),
            _ => http.Response('invalid json', 201),
          };
        });
        addTearDown(client.close);
        final repository = HabitRepository('http://localhost', client: client);
        await expectLater(
          repository.save({'name': 'Leitura'}),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.outcomeUnknown,
              'outcomeUnknown',
              isTrue,
            ),
          ),
        );
        expect(calls, 1);
      },
    );
  }

  test(
    'validação de cadastro é recuperável e não indica criação desconhecida',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'validation_error',
              'message': 'Nome inválido',
              'fields': {'name': 'Informe um nome.'},
            },
          }),
          422,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      addTearDown(client.close);
      await expectLater(
        HabitRepository('http://localhost', client: client).save({}),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.outcomeUnknown, 'outcomeUnknown', isFalse)
              .having((e) => e.message, 'message', 'Informe um nome.'),
        ),
      );
    },
  );

  test(
    'respostas inválidas do dashboard produzem erro compreensível',
    () async {
      final client = MockClient(
        (_) async => http.Response('{"habits":42}', 200),
      );
      addTearDown(client.close);
      await expectLater(
        HabitRepository('http://localhost', client: client).dashboard(),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
}
