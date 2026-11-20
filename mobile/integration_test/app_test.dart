import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest/main.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

// Teste desktop com servidor e banco reais, separados dos dados do usuário.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cria, conclui e preserva dados após reiniciar API e app', (
    tester,
  ) async {
    const project = String.fromEnvironment('HABITQUEST_PROJECT_DIR');
    expect(project, isNotEmpty, reason: 'Informe HABITQUEST_PROJECT_DIR.');
    final api = Directory('$project/api');
    final database = await Directory.systemTemp.createTemp('habitquest-e2e-');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final baseUrl = 'http://127.0.0.1:$port';
    final client = http.Client();
    Process? server;
    final log = StringBuffer();

    Future<void> startApi() async {
      server = await Process.start(
        '${api.path}/.venv/Scripts/python.exe',
        [
          '-m',
          'flask',
          '--app',
          'app',
          'run',
          '--no-reload',
          '--host',
          '127.0.0.1',
          '--port',
          '$port',
        ],
        workingDirectory: api.path,
        environment: {'HABITQUEST_DB': '${database.path}/e2e.sqlite3'},
      );
      server!.stdout.transform(utf8.decoder).listen(log.write);
      server!.stderr.transform(utf8.decoder).listen(log.write);
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline)) {
        try {
          final response = await client
              .get(Uri.parse('$baseUrl/api/v1/health'))
              .timeout(const Duration(seconds: 1));
          if (response.statusCode == 200) return;
        } on Exception {
          // A prontidão é confirmada pelo endpoint, não por um atraso fixo.
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      fail('A API não ficou pronta: $log');
    }

    Future<void> stopApi() async {
      server?.kill();
      await server?.exitCode.timeout(const Duration(seconds: 5));
      server = null;
    }

    addTearDown(() async {
      await stopApi();
      client.close();
      await database.delete(recursive: true);
    });
    await startApi();
    await tester.pumpWidget(HabitQuest(baseUrl: baseUrl));
    await tester.pumpAndSettle();
    expect(find.text('Crie seu primeiro hábito para começar.'), findsOneWidget);
    await tester.tap(find.text('Novo hábito'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Leitura integrada',
    );
    await tester.tap(find.text('3 dia(s)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 dia(s)').last);
    await tester.pumpAndSettle();
    final quantityField = find.widgetWithText(
      TextFormField,
      'Quantidade para concluir o dia',
    );
    final unitField = find.widgetWithText(
      TextFormField,
      'Unidade (vez, minutos, copos…)',
    );
    await tester.scrollUntilVisible(
      quantityField,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(quantityField, '20');
    await tester.scrollUntilVisible(
      unitField,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(unitField, 'minutos');
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
    expect(find.text('Leitura integrada'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Concluir hoje').hitTestable(),
      75,
    );
    await tester.tap(find.text('Concluir hoje'));
    await tester.pumpAndSettle();
    expect(find.text('Concluído hoje'), findsOneWidget);
    expect(find.textContaining('60 XP no total'), findsOneWidget);

    final dashboard = jsonDecode(
      (await client.get(Uri.parse('$baseUrl/api/v1/dashboard'))).body,
    ) as Map<String, dynamic>;
    final id = (dashboard['habits'] as List).single['id'];
    final repeat = await client.put(
      Uri.parse('$baseUrl/api/v1/habits/$id/checkins/today'),
      headers: {'X-Habit-Date': dashboard['local_date'] as String},
    );
    expect(repeat.statusCode, 200);
    expect(jsonDecode(repeat.body)['awarded_xp'], 0);

    // Exercita as novas mutações pela interface com HTTP/SQLite reais.
    await tester.pump(const Duration(seconds: 5));
    await tester.scrollUntilVisible(
      find.text('Desfazer registro de hoje').hitTestable(),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Desfazer registro de hoje'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect(find.text('0 de 20 minutos hoje'), findsOneWidget);
    expect(find.textContaining('0 XP no total'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.scrollUntilVisible(
      find.text('Registrar quantidade').hitTestable(),
      -100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Registrar quantidade'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '10');
    await tester.tap(find.text('Salvar progresso'));
    await tester.pumpAndSettle();
    expect(find.text('10 de 20 minutos hoje'), findsOneWidget);
    expect(find.textContaining('0 XP no total'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.scrollUntilVisible(
      find.text('Concluir hoje').hitTestable(),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Concluir hoje'));
    await tester.pumpAndSettle();
    expect(find.text('20 de 20 minutos hoje'), findsOneWidget);
    expect(find.textContaining('60 XP no total'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await stopApi();
    await expectLater(
      client.get(Uri.parse('$baseUrl/api/v1/health')),
      throwsA(isA<http.ClientException>()),
      reason: 'O servidor anterior deve estar encerrado antes da reabertura.',
    );
    await startApi();
    await tester.pumpWidget(HabitQuest(baseUrl: baseUrl));
    await tester.pumpAndSettle();
    expect(find.text('Leitura integrada'), findsOneWidget);
    expect(find.text('Concluído hoje'), findsOneWidget);
    expect(find.textContaining('60 XP no total'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
