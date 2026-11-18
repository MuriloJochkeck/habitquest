# HabitQuest

HabitQuest ajuda a transformar pequenas ações em rotina. Crie um hábito, defina quantos dias por semana quer praticá-lo e registre a realização do dia. O aplicativo mostra o calendário, o progresso da meta, a sequência e as conquistas.

O projeto tem um app Flutter com BLoC implementado com streams Dart e uma API Flask própria com SQLite. A API concede 10 XP por realização e 50 XP na primeira vez em que cada meta semanal é cumprida. O MVP usa um perfil local com fuso de São Paulo.

## Executar no Windows

Pré-requisitos: Python 3.12, Flutter com Dart 3.13 e um emulador Android ou Chrome. As dependências de Python estão em `api/requirements.txt` e as de Flutter em `mobile/pubspec.lock`.

No primeiro terminal, a partir da raiz:

```powershell
cd api
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements-dev.txt
.\.venv\Scripts\python -m flask --app app run --host 127.0.0.1 --port 5000
```

A migração cria `api/instance/habitquest.sqlite3` na primeira execução. O mesmo banco é reaberto nas próximas execuções. Para uma demonstração isolada, defina `$env:HABITQUEST_DB = 'instance/demo.sqlite3'` antes de iniciar a API.

No segundo terminal, para o emulador Android:

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

O emulador usa `http://10.0.2.2:5000` e o Chrome usa `http://localhost:5000`. Para outra configuração, passe `--dart-define=API_BASE_URL=<endereço>`. O Flask permite CORS da origem `http://localhost:7357` por padrão. A variável `HABITQUEST_WEB_ORIGIN` permite ajustar essa origem. O HTTP no Android está liberado para a variante debug.

## Verificar

```powershell
# Em api/
.\.venv\Scripts\python -m pytest

# Em mobile/
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Veja o [roteiro de demonstração e defesa](docs/APRESENTACAO.md) para os endpoints, o caminho completo de uma requisição e um exemplo de como comprovar a persistência e a proteção contra duplicidade. A [análise inicial](docs/PLANEJAMENTO.md) registra as premissas e decisões tomadas antes da implementação.
