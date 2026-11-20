import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'habit_pages.dart';
import 'habits_bloc.dart';
import 'habits_data.dart';
import 'quest_features.dart';
import 'reminders.dart';

const violet = Color(0xff6d28d9);
const ink = Color(0xff16112c);
const paper = Color(0xfff8f7fc);

void main() {
  const configured = String.fromEnvironment('API_BASE_URL');
  final host = kIsWeb
      ? 'localhost'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => '10.0.2.2',
          TargetPlatform.windows => '127.0.0.1',
          _ => 'localhost',
        };
  runApp(
    HabitQuest(baseUrl: configured.isEmpty ? 'http://$host:5000' : configured),
  );
}

class HabitQuest extends StatelessWidget {
  const HabitQuest({super.key, required this.baseUrl, this.repository});
  final String baseUrl;
  final HabitRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HabitQuest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: violet),
        scaffoldBackgroundColor: paper,
        appBarTheme: const AppBarTheme(
          backgroundColor: paper,
          foregroundColor: ink,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: QuestHome(baseUrl: baseUrl, repository: repository),
    );
  }
}

class QuestHome extends StatefulWidget {
  const QuestHome({super.key, required this.baseUrl, this.repository});
  final String baseUrl;
  final HabitRepository? repository;

  @override
  State<QuestHome> createState() => _QuestHomeState();
}

class _QuestHomeState extends State<QuestHome> with WidgetsBindingObserver {
  late final HabitRepository _repository =
      widget.repository ?? HabitRepository(widget.baseUrl);
  late final HabitsBloc _bloc = HabitsBloc(_repository);
  late final StreamSubscription<HabitsState> _effects;
  int _tab = 0;
  final ReminderService _reminders = ReminderService();
  String? _reminderError;

  Future<void> _syncReminders(Dashboard dashboard) async {
    await _reminders.sync(dashboard);
    if (mounted && _reminderError != _reminders.error) {
      setState(() => _reminderError = _reminders.error);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _effects = _bloc.states.listen((state) {
      if (!mounted) return;
      if (state.dashboard != null && !state.busy && state.error == null) {
        unawaited(_syncReminders(state.dashboard!));
      }
      final reward = state.reward;
      final message = reward != null && reward > 0
          ? (reward >= 60
                ? 'Meta batida! +$reward XP'
                : 'Realização registrada! +$reward XP')
          : state.notice;
      if (message != null) {
        if (reward != null) unawaited(HapticFeedback.lightImpact());
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });
    unawaited(_bloc.add(const HabitsRequested()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_bloc.add(const HabitsRequested()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_effects.cancel());
    _bloc.close();
    _reminders.close();
    if (widget.repository == null) _repository.close();
    super.dispose();
  }

  void _create() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => HabitForm(bloc: _bloc)));

  void _detail(Habit habit, String date) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HabitDetail(bloc: _bloc, habit: habit, date: date),
    ),
  );

  Future<void> _enableReminders() async {
    final error = await _reminders.enable();
    if (!mounted) return;
    if (error == null && _bloc.state.dashboard != null) {
      await _syncReminders(_bloc.state.dashboard!);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Lembretes ativados. ${_reminders.limitation}'),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  Future<void> _quantity(Habit habit) async {
    final expectedDate = _bloc.state.dashboard?.date;
    final form = GlobalKey<FormState>();
    var input = '${habit.todayQuantity}';
    final quantity = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Progresso de ${habit.name}'),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: input,
            onChanged: (value) => input = value,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Quantidade em ${habit.unit}',
              helperText:
                  'Meta: ${habit.dailyTarget}. Informe o total de hoje.',
            ),
            validator: (text) {
              final value = int.tryParse(text ?? '');
              return value == null || value < 0 || value > 1000000
                  ? 'Informe um inteiro de 0 a 1000000.'
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, int.parse(input));
              }
            },
            child: const Text('Salvar progresso'),
          ),
        ],
      ),
    );
    if (quantity != null && mounted) {
      await _bloc.add(
        HabitCheckInRequested(
          habit.id,
          quantity: quantity,
          expectedDate: expectedDate,
        ),
      );
    }
  }

  Future<void> _undo(Habit habit) async {
    final expectedDate = _bloc.state.dashboard?.date;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desfazer registro de hoje?'),
        content: const Text(
          'A quantidade de hoje será zerada. XP, metas e conquistas serão recalculados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desfazer'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _bloc.add(HabitUndoRequested(habit.id, expectedDate: expectedDate));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HabitsState>(
      stream: _bloc.states,
      initialData: _bloc.state,
      builder: (context, snapshot) {
        final state = snapshot.requireData;
        final data = state.dashboard;
        return Scaffold(
          appBar: AppBar(
            title: Semantics(
              label: 'HabitQuest',
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/brand-mark.png',
                    width: 34,
                    height: 34,
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'HabitQuest',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        color: ink,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Ativar lembretes',
                onPressed: _enableReminders,
                icon: const Icon(Icons.notifications_outlined),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: state.busy
                    ? null
                    : () => _bloc.add(const HabitsRequested()),
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) => setState(() => _tab = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.today_outlined),
                label: 'Hoje',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_rounded),
                label: 'Progresso',
              ),
              NavigationDestination(
                icon: Icon(Icons.emoji_events_outlined),
                label: 'Conquistas',
              ),
            ],
          ),
          floatingActionButton: _tab == 0 && data != null
              ? FloatingActionButton.extended(
                  onPressed: state.busy ? null : _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Novo hábito'),
                )
              : null,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: data == null && state.busy
                    ? const CircularProgressIndicator(
                        semanticsLabel: 'Carregando hábitos',
                      )
                    : RefreshIndicator(
                        onRefresh: () => _bloc.add(const HabitsRequested()),
                        child: ListView(
                          key: ValueKey(_tab),
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                          children: [
                            if (state.error case final message?)
                              Card(
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(message),
                                      TextButton(
                                        onPressed: () =>
                                            _bloc.add(const HabitsRequested()),
                                        child: const Text('Tentar novamente'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (data != null) ..._content(data, state),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _content(Dashboard data, HabitsState state) {
    final scheduled = data.habits
        .where((habit) => habit.scheduledToday)
        .toList();
    final other = data.habits.where((habit) => !habit.scheduledToday).toList();
    final completed = scheduled.where((habit) => habit.completed).length;
    Widget card(Habit habit) => HabitCard(
      habit: habit,
      weekStart: data.weekStart,
      pending: state.pendingId == habit.id,
      onOpen: () => _detail(habit, data.date),
      onCheck: state.busy || state.error != null || habit.completed
          ? null
          : () => _bloc.add(HabitCheckInRequested(habit.id)),
      onQuantity: state.busy || state.error != null
          ? null
          : () => _quantity(habit),
      onUndo: state.busy || state.error != null ? null : () => _undo(habit),
    );
    return switch (_tab) {
      0 => [
        QuestBanner(data: data, completed: completed),
        if (data.habits.any((habit) => habit.reminderTime != null))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _reminderError ?? _reminders.limitation,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 26),
        const PageHeading('Missões de hoje'),
        if (data.habits.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Crie seu primeiro hábito para começar.'),
          ),
        if (scheduled.isEmpty && data.habits.isNotEmpty)
          const Text(
            'Nenhuma missão programada para hoje. Aproveite seu dia de descanso.',
          ),
        for (final habit in scheduled) card(habit),
        if (other.isNotEmpty) ...[
          const SizedBox(height: 20),
          const PageHeading('Outros dias da sua rotina'),
          const Text(
            'Quer adiantar? Você também pode registrar estes hábitos hoje.',
          ),
          const SizedBox(height: 12),
          for (final habit in other) card(habit),
        ],
      ],
      1 => [
        const PageHeading('Seu progresso'),
        QuestBanner(data: data, completed: completed),
        const SizedBox(height: 20),
        if (data.weeklySummary case final summary?) ...[
          WeeklySummaryCard(summary: summary),
          const SizedBox(height: 20),
        ],
        if (data.habits.isEmpty)
          const Text('Seu progresso aparece aqui quando você cria um hábito.'),
        for (final habit in data.habits)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HabitCard(
                habit: habit,
                weekStart: data.weekStart,
                onOpen: () => _detail(habit, data.date),
              ),
              WeeklyHistory(history: habit.weeklyHistory),
              const SizedBox(height: 16),
            ],
          ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ArchivedPage(bloc: _bloc, date: data.date),
            ),
          ),
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Hábitos arquivados'),
        ),
      ],
      _ => [
        const PageHeading('Conquistas'),
        JourneyCard(
          data: data,
          onAvatar: state.busy || state.error != null
              ? null
              : (avatar) => _bloc.add(AvatarSelected(avatar)),
        ),
        const SizedBox(height: 20),
        if (data.achievements.isEmpty)
          const Text('Crie um hábito para descobrir seus primeiros desafios.'),
        for (final badge in data.achievements)
          Card(
            child: ListTile(
              leading: Icon(
                badge.unlocked
                    ? Icons.emoji_events_rounded
                    : Icons.lock_outline,
                color: badge.unlocked ? violet : null,
              ),
              title: Text(badge.title),
              subtitle: Text(
                '${badge.habit} · ${badge.unlocked ? 'Desbloqueada' : badge.requirement ?? badgeRequirement(badge.code)}',
              ),
            ),
          ),
      ],
    };
  }
}
