# HabitQuest — execução do planejamento

## Atualização de produto — 20/11/2026

O usuário informou que concluiu a validação manual da versão anterior no Chrome. A ocorrência histórica de tela em branco abaixo não é mais tratada como bloqueio dessa versão. A validação manual da nova versão no Chrome e Android será feita pelo usuário; os registros antigos de build/execução não comprovam as novas funcionalidades.

A atualização adiciona a logo aprovada e ícones derivados, dias programados, lembretes por hábito, metas diárias por quantidade, correção/remoção do registro de hoje, resumo semanal comparável e seleção de avatar com títulos por nível. Hábitos prontos e modo offline foram excluídos por solicitação. As regras atuais e limitações de notificação estão no README; o contrato atual está em openapi.json. As seções abaixo registram a entrega anterior e devem ser lidas como histórico quando houver diferença de escopo.

As alterações de schema são aditivas, preservando hábitos, realizações, conquistas e XP. Testes novos cobrem migração e reabertura, progresso parcial, undo, idempotência, concorrência, bônus/conquistas, calendário de lembretes e os novos fluxos Flutter.

| Verificação desta atualização | Resultado |
| --- | --- |
| API e contrato OpenAPI, com banco temporário | 61 testes passaram |
| Flutter: BLoC, repositório, widgets e planejamento de lembretes | 23 testes passaram |
| Integração Windows com API/SQLite reais | 1 teste passou: criar meta de 20 minutos, concluir, repetir sem duplicar XP, desfazer, registrar 10 minutos sem XP, concluir novamente e reiniciar preservando dados/XP |
| Análise estática e formatação Dart | Sem problemas; arquivos formatados |
| Builds Windows release e Web release | Geradas com o plugin e assets novos; Web mantém aviso de fonte Cupertino ausente já registrado anteriormente |
| Revisão e whitespace | Revisão independente levou à proteção da data original de diálogos e aviso de reversão de XP; `git diff --check` sem erros |

As notificações entregues pelo sistema e as permissões reais ainda exigem conferência no dispositivo. Os testes de widgets usam o registrador Dart do plugin com canal nativo simulado; os testes de planejamento verificam dias, horários, fuso, supressão de hoje e virada de ano. As limitações de janela de 30 dias/400 alarmes Android e entrega com app aberto no Windows/Web estão visíveis na interface e no README. O banco pessoal não foi usado pelos testes.

Este registro compara o MVP de [PLANEJAMENTO.md](PLANEJAMENTO.md) com a implementação e suas verificações. O planejamento original é mantido como histórico. O [README](../README.md) contém os comandos atuais e [APRESENTACAO.md](APRESENTACAO.md), o roteiro de defesa.

## Escopo entregue

Flutter com BLoC em streams Dart, pacote HTTP, API Flask e SQLite, com perfil local único no fuso de São Paulo. Os widgets não concedem XP: a API calcula e persiste recompensas na mesma transação das realizações. O suporte Windows já preparado foi preservado e integrado à validação.

| Critério | Implementação e evidência |
| --- | --- |
| RF01 — criar | Formulário com catálogos, meta 1–7 e validação; testes API, widgets e integração real |
| RF02 — consultar/editar | Lista, detalhe e edição persistida; meta imutável; teste de fluxo edita sem enviar meta |
| RF03 — arquivar | Confirmação, remoção da lista ativa e histórico consultável; testes de persistência/API e fluxo Flutter |
| RF04 — realizar hoje | PUT com data esperada do dashboard; confirmação vem do servidor; teste integrado real |
| RF05 — duplicidade | Unicidade e transação SQLite, bônus semanal único, proteção contra duplo toque e cadastro com confirmação desconhecida; testes concorrentes API e BLoC |
| RF06 — frequência | Calendário mensal, semana atual e até oito semanas recentes, inclusive zeros; semanas parciais sinalizadas; aderência usa todo o histórico elegível |
| RF07 — recompensas | 10 XP diário, 50 XP por meta semanal, nível a cada 100 XP e quatro conquistas; testes de metas, ano e sequências de 7/30 dias |
| RF08 — persistência | Reabertura do mesmo banco sem recriação; testes API e reinício real de API e app no teste integrado |
| RF09 — falhas | Carregamento, vazio, validação, indisponibilidade, tentar novamente, preservação dos dados e consulta após cadastro incerto; testes de repositório, BLoC e widgets |
| RF10 — integração | Flutter → HTTP real → Flask → SQLite em banco temporário e porta livre; criar, concluir, repetir PUT e reabrir com mesmos dados/XP |

O contrato [OpenAPI 3.1](openapi.json) documenta as rotas e os schemas reais, incluindo `X-Habit-Date`, `weekly_history` e requisitos de conquistas. Os testes conferem referências, rotas Flask e respostas reais contra o subconjunto de JSON Schema utilizado no documento. Não se trata de um validador OpenAPI genérico.

## Correções concluídas nesta revisão

- Frequência histórica semanal e requisitos de conquistas sincronizados entre API, modelos e interface.
- Cadastro com timeout, perda de conexão, erro de servidor ou resposta inválida exige conferir a lista antes de um novo envio; não há repetição automática do POST.
- Explicação explícita de meta imutável, registros somente de hoje e ausência de remoção/retroativos.
- Remoção da declaração duplicada no manifesto Android debug.
- Calendário adaptado para tela de 320 pixels com texto 2× e marcador não cromático de realização.
- Callbacks de atualização do detalhe/arquivados corrigidos para não retornar `Future` dentro de `setState`.
- Banco de demonstração com histórico fictício, semana sem leitura, conquistas e hábito arquivado, criado sem sobrescrever arquivos existentes.

## Verificações

Os comandos abaixo partem das pastas indicadas. O teste integrado desktop exige Windows, Visual Studio C++, a venv Python preparada e o caminho absoluto da cópia do projeto.

```powershell
# api/
.\.venv\Scripts\python -m pytest --basetemp=instance/pytest-local --tb=short

# mobile/
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --concurrency=1
flutter test integration_test/app_test.dart -d windows --dart-define=HABITQUEST_PROJECT_DIR=C:/Projetos/habitquest
flutter build windows
flutter build web
flutter build apk --debug
```

O teste integrado usa uma API em processo separado, sem reloader, e comprova que ela está indisponível antes de reiniciar. A pasta e o banco temporários são removidos ao terminar; os dados pessoais e o banco da porta 5000 não são usados. Os testes da API controlam o relógio para verificar as fronteiras de data sem alterar o relógio da máquina.

| Verificação executada | Resultado |
| --- | --- |
| API: pytest com banco e relógio controlados | 27 testes passaram |
| Flutter: testes de repositório, BLoC e widgets, `--concurrency=1` | 15 testes passaram |
| Integração desktop com HTTP/SQLite reais e reinício | 1 teste passou; endpoint indisponível comprovado antes de reiniciar |
| `flutter analyze` | Sem problemas |
| `dart format --output=none --set-exit-if-changed lib test integration_test` | Sem alterações necessárias |
| `flutter build windows` | Build release gerada; aplicativo reaberto com a API atualizada e o mesmo banco |
| `flutter build web` | Build gerada; emitiu aviso de referência a fonte Cupertino ausente, sem impedir compilação. O app utiliza ícones Material |
| `flutter build apk --debug` | Bloqueada em downloads do Gradle; não há APK atualizado validado |
| Gerador de demonstração | Teste passou e `api/instance/apresentacao.sqlite3` foi criado separadamente, sem alterar o banco pessoal |
| `git diff --check` e revisão independente | Sem erros de whitespace; encontrados e corrigidos marcador visual do calendário e comprovação de reinício |

### Pendência externa: Android

A build chegou à tarefa `:integration_test:extractDebugAnnotations`, que precisava dos artefatos oficiais `com.android.tools.external.com-intellij:intellij-core:32.1.0` e `kotlin-compiler:32.1.0`. Os downloads ficaram sem progresso por vários minutos. A compilação foi interrompida para diagnóstico. Tentativas de transferência direta e por intervalos terminaram em timeout ou `RemoteDisconnected`; nenhum artefato sem checksum oficial conferido foi utilizado, e nenhum repositório ou versão do projeto foi alterado para contornar a falha.

O emulador `Medium_Phone_API_36.1` iniciou e completou o boot, mas o APK novo não foi instalado por falta dessa build. O APK existente de uma execução anterior não foi considerado evidência. Quando a conexão com o repositório Maven estiver normalizada, execute `flutter build apk --debug` e `flutter run -d <id-do-emulador>` em `mobile/`. Os logs do diagnóstico estão em `api/instance/android-build.log` e `api/instance/android-resume.log`, fora do Git. A entrega não está integralmente validada no Android. Após nova tentativa, o usuário solicitou cancelar a execução e fazer commit do trabalho existente, preservando essa pendência.

A integração funcional real foi comprovada no Windows. No Web, a compilação e o contrato CORS passaram; a inspeção posterior no navegador integrado mostrou uma tela em branco, cujo diagnóstico foi interrompido pelo pedido de cancelamento. A execução Web permanece sem validação funcional. A validação de layout incluiu calendário de 320 pixels com texto 2×; não foi realizado ensaio humano com leitor de tela nem teste em dispositivo físico.

## Limites preservados do planejamento

Sem login, múltiplos usuários, ranking, loja, notificações, sincronização offline, quantidades parciais, exclusão/retroativos ou publicação em lojas. Não foi criada infraestrutura pública nem executado deploy. O perfil único e o HTTP local atendem à demonstração acadêmica; distribuição pública e configuração release Android não fazem parte desta entrega.

A estrutura foi mantida proporcional ao MVP: um BLoC e repositório Dart compartilhados, módulos Flask e perfil fixo, sem reproduzir diretórios/classes/tabelas que eram apenas sugestões no plano. As regras e os resultados observáveis foram preservados.
