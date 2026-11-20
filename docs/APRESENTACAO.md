# Apresentação e defesa do HabitQuest

## 1. Finalidade

O HabitQuest ajuda quem tem dificuldade de manter uma rotina. A pessoa transforma uma intenção, como “Ler por 20 minutos”, em uma meta semanal e acompanha os dias em que cumpriu o hábito. XP, níveis e conquistas tornam o progresso visível.

## 2. API desenvolvida

Prefixo `/api/v1`. As rotas retornam JSON.

| Método | Caminho | Resultado |
| --- | --- | --- |
| GET | `/health` | Confirma que a API acessa o banco |
| GET | `/profile` | Perfil local e fuso |
| POST | `/habits` | Cria hábito e retorna 201 |
| GET | `/habits?status=active` | Lista hábitos ativos, arquivados ou todos |
| GET | `/habits/{id}` | Consulta o hábito e suas métricas |
| PATCH | `/habits/{id}` | Edita nome, descrição, cor e ícone |
| POST | `/habits/{id}/archive` | Arquiva o hábito e preserva seu histórico |
| PUT | `/habits/{id}/checkins/today` | Registra hoje, retorna 201 se criou ou 200 se já existia |
| GET | `/habits/{id}/checkins?from=AAAA-MM-DD&to=AAAA-MM-DD` | Lista realizações em um período inclusivo |
| GET | `/dashboard` | Traz hábitos, data, XP, nível e conquistas |
| GET | `/achievements` | Lista conquistas por hábito |

## 3. Da requisição à resposta

Em [routes.py](../api/app/routes.py), `checkin_today` abre uma transação de escrita, localiza o hábito e confere se está ativo. A API calcula a data no fuso de São Paulo. Se o cabeçalho `X-Habit-Date` divergir da data atual, a rota retorna 409 e o app atualiza a lista.

Em [progress.py](../api/app/progress.py), `record_checkin` insere o registro único, concede 10 XP e acrescenta 50 XP na primeira vez em que a meta é cumprida na semana. Os registros, o XP e as conquistas são persistidos na mesma transação. As chaves do [esquema SQLite](../api/migrations/001_initial.sql) dão suporte a essa garantia.

Para meta de um dia, o primeiro PUT retorna 201, `created: true` e `awarded_xp: 60`. A repetição na mesma data retorna 200, `created: false` e `awarded_xp: 0`.

## 4. Integração com Flutter

1. Em [main.dart](../mobile/lib/main.dart), tocar em **Concluir hoje** dispara `HabitCheckInRequested`.
2. Em [habits_bloc.dart](../mobile/lib/habits_bloc.dart), o BLoC emite o estado pendente e chama o repositório.
3. Em [habits_data.dart](../mobile/lib/habits_data.dart), `HabitRepository.checkInToday` envia o PUT com o pacote `http` e lê o XP concedido no JSON.
4. O BLoC busca o dashboard atualizado. A interface observa o stream e mostra a conclusão, a nova pontuação e a confirmação.

## 5. Demonstração e defesa

1. Inicie API e app conforme o [README](../README.md), usando um banco de demonstração. O comando `seed_demo.py --database instance/apresentacao.sqlite3` cria exemplos fictícios com cinco semanas de histórico e recusa sobrescrever arquivos existentes.
2. Crie “Ler por 20 minutos” com meta semanal de um dia e toque em **Concluir hoje**. Mostre os 60 XP, a semana e as conquistas.
3. Repita o PUT pelo terminal para mostrar que a pontuação permanece igual.
4. Reinicie a API e atualize o app para demonstrar a persistência.
5. Mostre o caminho do botão até a resposta da API nos arquivos acima.
6. Em **Progresso**, mostre frequência semanal, semanas sem realização e semanas parciais. Em **Hábitos arquivados**, abra o histórico preservado. A aderência desconsidera semanas parciais e limita a contribuição de cada semana à meta.
7. Mostre o [contrato OpenAPI](openapi.json) e os [resultados da entrega](ENTREGA.md). A suíte integrada desktop comprova criação, realização, repetição sem XP adicional e reabertura após reiniciar o servidor.

Limites para explicar: perfil local único sem login; meta não editável; somente registros do dia determinado pela API, sem remoção e sem lançamento retroativo. Se uma resposta de cadastro se perder, o formulário orienta conferir a lista antes de novo cadastro. Hospedagem pública, autenticação, sincronização offline e publicação nas lojas ficam para evolução.

```powershell
$base = 'http://localhost:5000/api/v1'
$dashboard = Invoke-RestMethod "$base/dashboard"
$habit = $dashboard.habits | Where-Object { $_.name -eq 'Ler por 20 minutos' } | Select-Object -First 1
Invoke-RestMethod -Method Put "$base/habits/$($habit.id)/checkins/today" -Headers @{
    'X-Habit-Date' = $dashboard.local_date
}
```

Perguntas para ensaiar:

- **Por que BLoC?** Eventos e estados tornam carregamento, falha e sucesso verificáveis. O repositório concentra as chamadas HTTP.
- **Como evitar XP duplicado?** O SQLite garante um registro por dia e um bônus por semana por hábito. A transação mantém as gravações coerentes.
- **Qual é a diferença entre frequência e sequência?** Frequência conta realizações em um período. Sequência conta dias consecutivos.
- **E se a conexão cair?** O app mostra a falha e permite atualizar para recuperar o estado real do servidor.
- **Por que SQLite?** O arquivo local atende ao escopo acadêmico e facilita a demonstração e a persistência entre reinícios.
