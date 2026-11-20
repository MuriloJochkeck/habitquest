# HabitQuest

HabitQuest ajuda a transformar pequenas ações em rotina. Crie um hábito, defina quantos dias por semana quer praticá-lo e registre a realização do dia. O aplicativo mostra o calendário, o progresso da meta, a sequência e as conquistas.

O projeto tem um app Flutter com BLoC implementado com streams Dart e uma API Flask própria com SQLite. A API concede 10 XP por realização e 50 XP na primeira vez em que cada meta semanal é cumprida. O MVP usa um perfil local com fuso de São Paulo.

## Executar no Windows

Instale Python 3.12 e Flutter com Dart 3.13. Para o aplicativo nativo, instale o Visual Studio com a carga de trabalho **Desenvolvimento para desktop com C++** e verifique o ambiente com `flutter doctor -v`. Veja a [configuração oficial do Flutter para Windows](https://docs.flutter.dev/platform-integration/windows/setup).

No primeiro terminal, a partir da raiz:

```powershell
cd api
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements-dev.txt
.\.venv\Scripts\python -m flask --app app run --host 127.0.0.1 --port 5000
```

A migração cria `api/instance/habitquest.sqlite3` na primeira execução. O mesmo banco é reaberto nas próximas execuções. Para uma demonstração isolada, defina `$env:HABITQUEST_DB = 'instance/demo.sqlite3'` antes de iniciar a API.

No segundo terminal, execute o aplicativo nativo:

```powershell
cd mobile
flutter pub get
flutter run -d windows
```

Para gerar o executável de release, rode `flutter build windows` em `mobile`. No Windows x64, abra `build\windows\x64\runner\Release\habitquest.exe` enquanto a API estiver rodando. Mantenha o executável junto das DLLs e da pasta `data` que foram geradas na mesma pasta.

Para o emulador Android:

```powershell
cd mobile
flutter pub get
flutter devices
flutter run -d <id-do-emulador>
```

Para o Chrome, use:

```powershell
flutter run -d chrome --web-hostname localhost --web-port 7357
```

O Windows usa `http://127.0.0.1:5000`, o emulador usa `http://10.0.2.2:5000` e o Chrome usa `http://localhost:5000`. Para outra configuração, passe `--dart-define=API_BASE_URL=<endereço>`. O Flask permite CORS da origem `http://localhost:7357` por padrão. A variável `HABITQUEST_WEB_ORIGIN` permite ajustar essa origem. O HTTP no Android está liberado para a variante debug.

## Verificar

```powershell
# Em api/
.\.venv\Scripts\python -m pytest

# Em mobile/
flutter analyze
flutter test
flutter build windows
flutter build web
flutter build apk --debug
```

O teste de integração desktop inicia uma API real em porta livre, usa banco temporário e reinicia API e aplicativo para comprovar a persistência. Não usa o banco pessoal nem exige a API da porta 5000:

```powershell
cd mobile
flutter test integration_test/app_test.dart -d windows --dart-define=HABITQUEST_PROJECT_DIR=C:/Projetos/habitquest
```

Troque `HABITQUEST_PROJECT_DIR` pelo caminho absoluto da sua cópia. Execute builds e testes em sequência em máquinas com pouca memória. Se o pytest não conseguir usar a pasta temporária do sistema, execute em `api/` com `--basetemp=instance/pytest-local` (essa pasta é exclusiva dos testes e será recriada pelo pytest).

## Dados de demonstração

Para mostrar histórico, semanas sem realização e conquistas sem esperar vários dias, crie um banco separado com dados fictícios:

```powershell
cd api
.\.venv\Scripts\python seed_demo.py --database instance/apresentacao.sqlite3
$env:HABITQUEST_DB = (Resolve-Path instance/apresentacao.sqlite3).Path
.\.venv\Scripts\python -m flask --app app run --host 127.0.0.1 --port 5000
```

O gerador recusa sobrescrever qualquer arquivo existente. Para voltar ao banco habitual, encerre a API, execute `Remove-Item Env:HABITQUEST_DB` e inicie a API novamente. Apenas um servidor deve ocupar a porta 5000.

O progresso exibe até oito semanas recentes por hábito, incluindo semanas sem realizações. Semanas parciais são sinalizadas; a aderência usa todas as semanas completas elegíveis. A meta é imutável e os registros são somente de hoje, sem remoção. Após um cadastro sem confirmação, confira a lista antes de criar novamente.

O [contrato OpenAPI](docs/openapi.json) descreve os campos e erros atuais. Consulte a [situação da entrega](docs/ENTREGA.md) para a rastreabilidade dos requisitos e os limites de validação.

Veja o [roteiro de demonstração e defesa](docs/APRESENTACAO.md) para os endpoints, o caminho completo de uma requisição e um exemplo de como comprovar a persistência e a proteção contra duplicidade. A [análise inicial](docs/PLANEJAMENTO.md) registra as premissas e decisões tomadas antes da implementação.
