import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'habit_pages.dart';
import 'habits_bloc.dart';
import 'habits_data.dart';

const violet = Color(0xff6d28d9);
const ink = Color(0xff16112c);
const paper = Color(0xfff8f7fc);

void main() {
  const configured = String.fromEnvironment('API_BASE_URL');
  final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _effects = _bloc.states.listen((state) {
      if (!mounted) return;
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
            title: const Text(
              '✦  HabitQuest',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
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
    final completed = data.habits.where((habit) => habit.completed).length;
    return switch (_tab) {
      0 => [
        QuestBanner(data: data, completed: completed),
        const SizedBox(height: 26),
        const PageHeading('Missões de hoje'),
        if (data.habits.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Crie seu primeiro hábito para começar.'),
          ),
        for (final habit in data.habits)
          HabitCard(
            habit: habit,
            weekStart: data.weekStart,
            pending: state.pendingId == habit.id,
            onOpen: () => _detail(habit, data.date),
            onCheck: state.busy || state.error != null || habit.completed
                ? null
                : () => _bloc.add(HabitCheckInRequested(habit.id)),
          ),
      ],
      1 => [
        const PageHeading('Seu progresso'),
        QuestBanner(data: data, completed: completed),
        const SizedBox(height: 20),
        if (data.habits.isEmpty)
          const Text('Seu progresso aparece aqui quando você cria um hábito.'),
        for (final habit in data.habits)
          HabitCard(
            habit: habit,
            weekStart: data.weekStart,
            onOpen: () => _detail(habit, data.date),
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
                '${badge.habit} · ${badge.unlocked ? 'Desbloqueada' : badgeRequirement(badge.code)}',
              ),
            ),
          ),
      ],
    };
  }
}
