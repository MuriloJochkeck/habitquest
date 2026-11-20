import 'dart:async';

import 'package:flutter/material.dart';

import 'habits_bloc.dart';
import 'habits_data.dart';

const habitIcons = {
  'spark': Icons.auto_awesome_rounded,
  'book': Icons.menu_book_rounded,
  'fitness': Icons.fitness_center_rounded,
  'water': Icons.water_drop_rounded,
  'mind': Icons.self_improvement_rounded,
};
const habitColors = {
  'violet': Color(0xff6d28d9),
  'mint': Color(0xff047857),
  'amber': Color(0xff92400e),
  'blue': Color(0xff1d4ed8),
  'rose': Color(0xffbe185d),
};
const weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

String isoDay(DateTime value) => value.toIso8601String().substring(0, 10);
String displayDate(String value) => value.split('-').reversed.join('/');
String badgeRequirement(String code) => switch (code) {
  'first_checkin' => 'Conclua o hábito pela primeira vez',
  'first_weekly_goal' => 'Cumpra a meta semanal',
  'streak_7' => 'Conclua por 7 dias seguidos',
  _ => 'Conclua por 30 dias seguidos',
};

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title,
      style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w900),
    ),
  );
}

class QuestBanner extends StatelessWidget {
  const QuestBanner({super.key, required this.data, required this.completed});
  final Dashboard data;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final levelXp = data.xp % 100;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff231549), Color(0xff5322a5)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${displayDate(data.date)}  ·  NÍVEL ${data.level}',
            style: const TextStyle(
              color: Color(0xffe1d0ff),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pequenos passos,\ngrande constância.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 27,
              height: 1.12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '$completed de ${data.habits.where((habit) => habit.scheduledToday).length} missões feitas hoje',
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: levelXp / 100),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 360),
            builder: (context, value, child) => LinearProgressIndicator(
              value: value,
              minHeight: 8,
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xfffbbf24),
              backgroundColor: const Color(0xff7657aa),
              semanticsLabel: 'Progresso para o próximo nível',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${data.xp} XP no total  ·  $levelXp/100 para subir',
            style: const TextStyle(color: Color(0xffe1d0ff)),
          ),
        ],
      ),
    );
  }
}

class HabitCard extends StatelessWidget {
  const HabitCard({
    super.key,
    required this.habit,
    required this.weekStart,
    required this.onOpen,
    this.onCheck,
    this.pending = false,
    this.onUndo,
    this.onQuantity,
  });
  final Habit habit;
  final DateTime weekStart;
  final VoidCallback? onOpen, onCheck;
  final VoidCallback? onUndo, onQuantity;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final color = habitColors[habit.color] ?? habitColors.values.first;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xffe8e2f3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              onTap: onOpen,
              contentPadding: const EdgeInsets.symmetric(horizontal: 3),
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: .10),
                child: Icon(habitIcons[habit.icon], color: color),
              ),
              title: Text(
                habit.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${habit.count} de ${habit.target} dias na semana · ${habit.streak} seguidos',
              ),
              trailing: onOpen == null ? null : const Icon(Icons.chevron_right),
            ),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (var i = 0; i < weekdays.length; i++)
                  _DayChip(
                    label: weekdays[i],
                    checked: habit.weekDays.contains(
                      isoDay(
                        DateTime.utc(
                          weekStart.year,
                          weekStart.month,
                          weekStart.day + i,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (habit.reminderTime != null || habit.scheduledDays.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  [
                    if (habit.scheduledDays.isNotEmpty)
                      habit.scheduledDays
                          .map((day) => weekdays[day - 1])
                          .join(' · '),
                    if (habit.reminderTime != null)
                      'Lembrete ${habit.reminderTime}',
                  ].join('  •  '),
                ),
              ),
            if (habit.dailyTarget > 1) ...[
              const SizedBox(height: 12),
              Text(
                '${habit.todayQuantity} de ${habit.dailyTarget} ${habit.unit} hoje',
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: (habit.todayQuantity / habit.dailyTarget).clamp(0, 1),
              ),
              if (onQuantity != null)
                OutlinedButton.icon(
                  onPressed: pending ? null : onQuantity,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Registrar quantidade'),
                ),
            ],
            if (habit.completed || pending || onCheck != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onCheck,
                icon: Icon(
                  habit.completed ? Icons.check_circle : Icons.bolt_rounded,
                ),
                label: Text(
                  pending
                      ? 'Registrando…'
                      : habit.completed
                      ? 'Concluído hoje'
                      : 'Concluir hoje',
                ),
              ),
            ],
            if (onUndo != null && (habit.completed || habit.todayQuantity > 0))
              TextButton.icon(
                onPressed: pending ? null : onUndo,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Desfazer registro de hoje'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.checked,
    this.compact = false,
  });
  final String label;
  final bool checked, compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, ${checked ? 'realizado' : 'sem realização'}',
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: checked ? const Color(0xffe1faef) : const Color(0xfff0edf6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 7, vertical: 6),
        child: Text(
          checked && !compact ? '✓ $label' : label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: compact && checked ? FontWeight.w700 : null,
            decoration: compact && checked ? TextDecoration.underline : null,
            color: checked ? const Color(0xff065f46) : const Color(0xff534563),
          ),
        ),
      ),
    ),
  );
}

class HabitForm extends StatefulWidget {
  const HabitForm({super.key, required this.bloc, this.habit});
  final HabitsBloc bloc;
  final Habit? habit;
  @override
  State<HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends State<HabitForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.habit?.name);
  late final _description = TextEditingController(
    text: widget.habit?.description,
  );
  late int _target = widget.habit?.target ?? 3;
  late String _icon = widget.habit?.icon ?? 'spark';
  late String _color = widget.habit?.color ?? 'violet';
  late final _quantity = TextEditingController(
    text: '${widget.habit?.dailyTarget ?? 1}',
  );
  late final _unit = TextEditingController(text: widget.habit?.unit ?? 'vez');
  late final Set<int> _days = {...?widget.habit?.scheduledDays};
  late String? _reminder = widget.habit?.reminderTime;
  bool _saving = false;
  bool _confirmationUnknown = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _quantity.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_days.isNotEmpty && _days.length < _target) {
      setState(
        () => _error =
            'Selecione pelo menos $_target dias para atender à meta semanal.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final event = HabitSaveRequested({
      'name': _name.text,
      'description': _description.text,
      'icon': _icon,
      'color': _color,
      if (widget.habit == null) 'weekly_target': _target,
      'scheduled_days': _days.toList()..sort(),
      'reminder_time': _reminder,
      if (widget.habit == null) 'daily_target': int.parse(_quantity.text),
      if (widget.habit == null) 'unit': _unit.text.trim(),
    }, id: widget.habit?.id);
    unawaited(widget.bloc.add(event));
    final result = await event.result.future;
    if (!mounted) return;
    if (result == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _confirmationUnknown = event.outcomeUnknown;
      _error = event.outcomeUnknown
          ? 'Não foi possível confirmar o cadastro. Confira na lista se o hábito foi criado antes de cadastrar novamente.'
          : result;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.habit == null ? 'Novo hábito' : 'Editar hábito'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  controller: _name,
                  maxLength: 80,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Nome do hábito',
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Informe um nome.' : null,
                ),
                TextFormField(
                  controller: _description,
                  maxLength: 280,
                  maxLines: 2,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Descrição (opcional)',
                  ),
                ),
                DropdownButtonFormField<int>(
                  initialValue: _target,
                  decoration: const InputDecoration(labelText: 'Meta semanal'),
                  onChanged: widget.habit != null || _saving
                      ? null
                      : (value) => setState(() => _target = value!),
                  items: List.generate(
                    7,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text('${i + 1} dia(s)'),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'A meta integral vale desde a criação. A meta não pode ser alterada: para outra meta, arquive o hábito e crie outro. '
                    'Os registros são de hoje. Você pode corrigir quantidades e desfazer o registro do dia; XP e conquistas acompanham a alteração.',
                  ),
                ),
                const Text(
                  'Dias programados',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Text(
                  'Sem seleção: rotina flexível. Você também pode realizar fora dos dias programados.',
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var day = 1; day <= 7; day++)
                      FilterChip(
                        label: Text(weekdays[day - 1]),
                        selected: _days.contains(day),
                        onSelected: _saving
                            ? null
                            : (selected) => setState(() {
                                if (selected) {
                                  _days.add(day);
                                } else {
                                  _days.remove(day);
                                }
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _quantity,
                  enabled: widget.habit == null && !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantidade para concluir o dia',
                    helperText: 'Ex.: 20 minutos ou 8 copos. Use 1 para uma conclusão simples.',
                  ),
                  validator: (value) {
                    final amount = int.tryParse(value ?? '');
                    return amount == null || amount < 1 || amount > 1000000
                        ? 'Informe um inteiro de 1 a 1000000.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _unit,
                  maxLength: 24,
                  enabled: widget.habit == null && !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Unidade (vez, minutos, copos…)',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Informe a unidade.'
                      : null,
                ),
                if (widget.habit != null)
                  const Text(
                    'A quantidade e a unidade são preservadas para manter o histórico comparável.',
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(
                    _reminder == null
                        ? 'Sem lembrete'
                        : 'Lembrar às $_reminder',
                  ),
                  subtitle: const Text(
                    'Horário de São Paulo. Ative as notificações na tela inicial.',
                  ),
                  trailing: _reminder == null
                      ? null
                      : IconButton(
                          tooltip: 'Remover lembrete',
                          onPressed: _saving
                              ? null
                              : () => setState(() => _reminder = null),
                          icon: const Icon(Icons.close),
                        ),
                  onTap: _saving
                      ? null
                      : () async {
                          final parts = _reminder?.split(':');
                          final time = await showTimePicker(
                            context: context,
                            initialTime: parts == null
                                ? const TimeOfDay(hour: 20, minute: 0)
                                : TimeOfDay(
                                    hour: int.parse(parts[0]),
                                    minute: int.parse(parts[1]),
                                  ),
                          );
                          if (time != null && mounted) {
                            setState(
                              () => _reminder =
                                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                            );
                          }
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _icon,
                  decoration: const InputDecoration(labelText: 'Ícone'),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _icon = value!),
                  items: [
                    for (final (key, name) in [
                      ('spark', 'Estrela'),
                      ('book', 'Livro'),
                      ('fitness', 'Exercício'),
                      ('water', 'Água'),
                      ('mind', 'Bem-estar'),
                    ])
                      DropdownMenuItem(
                        value: key,
                        child: Row(
                          children: [
                            Icon(habitIcons[key]),
                            const SizedBox(width: 12),
                            Text(name),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _color,
                  decoration: const InputDecoration(labelText: 'Cor'),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _color = value!),
                  items: [
                    for (final (key, name) in [
                      ('violet', 'Violeta'),
                      ('mint', 'Verde'),
                      ('amber', 'Âmbar'),
                      ('blue', 'Azul'),
                      ('rose', 'Rosa'),
                    ])
                      DropdownMenuItem(
                        value: key,
                        child: Row(
                          children: [
                            Icon(Icons.circle, color: habitColors[key]),
                            const SizedBox(width: 12),
                            Text(name),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _saving || _confirmationUnknown ? null : _save,
                  child: Text(_saving ? 'Salvando…' : 'Salvar hábito'),
                ),
                if (_confirmationUnknown)
                  TextButton(
                    onPressed: () {
                      unawaited(widget.bloc.add(const HabitsRequested()));
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(context);
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Confira se o hábito aparece na lista antes de criar outro.',
                          ),
                        ),
                      );
                    },
                    child: const Text('Conferir lista de hábitos'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HabitDetail extends StatefulWidget {
  const HabitDetail({
    super.key,
    required this.bloc,
    required this.habit,
    required this.date,
  });
  final HabitsBloc bloc;
  final Habit habit;
  final String date;
  @override
  State<HabitDetail> createState() => _HabitDetailState();
}

class _HabitDetailState extends State<HabitDetail> {
  late DateTime _month = DateTime.parse(widget.date);
  late Future<(Habit, List<String>)> _data = _load();
  bool _archiving = false;

  Future<(Habit, List<String>)> _load() async {
    final first = DateTime.utc(_month.year, _month.month);
    final last = DateTime.utc(_month.year, _month.month + 1, 0);
    final habit = await widget.bloc.repository.detail(widget.habit.id);
    final history = await widget.bloc.repository.history(
      habit.id,
      isoDay(first),
      isoDay(last),
    );
    return (habit, history);
  }

  void _reload() => setState(() {
    _data = _load();
  });

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arquivar hábito?'),
        content: const Text(
          'O histórico e o XP ficam disponíveis. O hábito sai da lista de hoje.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Arquivar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _archiving = true);
    final event = HabitArchiveRequested(widget.habit.id);
    unawaited(widget.bloc.add(event));
    final error = await event.result.future;
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() => _archiving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _manageArchived({required bool delete}) async {
    if (_archiving) return;
    if (delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            Icons.delete_forever_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Excluir hábito permanentemente?'),
          content: Text(
            '“${widget.habit.name}”, todo o histórico, quantidades, XP e conquistas desse hábito serão excluídos. Seu nível pode diminuir. Esta ação não pode ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir tudo'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _archiving = true);
    final Future<String?> result;
    if (delete) {
      final event = HabitDeleteRequested(widget.habit.id);
      unawaited(widget.bloc.add(event));
      result = event.result.future;
    } else {
      final event = HabitRestoreRequested(widget.habit.id);
      unawaited(widget.bloc.add(event));
      result = event.result.future;
    }
    final error = await result;
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() => _archiving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detalhes do hábito')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: FutureBuilder(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator();
            }
            if (snapshot.hasError) {
              return RetryPanel(error: snapshot.error, retry: _reload);
            }
            final (habit, days) = snapshot.requireData;
            final monthStart = DateTime.utc(_month.year, _month.month);
            final daysInMonth = DateTime.utc(
              _month.year,
              _month.month + 1,
              0,
            ).day;
            final monthLabel =
                '${_month.month.toString().padLeft(2, '0')}/${_month.year}';
            final adherence = habit.adherence;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                PageHeading(habit.name),
                if (habit.description.isNotEmpty) Text(habit.description),
                if (habit.archived) ...[
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Hábito arquivado',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Text(
                            'Volte a praticar preservando seus dados ou exclua o hábito permanentemente.',
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: _archiving
                                ? null
                                : () => _manageArchived(delete: false),
                            icon: const Icon(Icons.unarchive_outlined),
                            label: const Text('Desarquivar hábito'),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .error,
                            ),
                            onPressed: _archiving
                                ? null
                                : () => _manageArchived(delete: true),
                            icon: const Icon(Icons.delete_forever_outlined),
                            label: const Text('Excluir permanentemente'),
                          ),
                          if (_archiving)
                            const LinearProgressIndicator(
                              semanticsLabel: 'Atualizando hábito',
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text('${habit.count} de ${habit.target} dias nesta semana'),
                Text('Sequência atual: ${habit.streak} dia(s)'),
                Text(
                  adherence == null
                      ? 'Sem uma semana completa para calcular a aderência'
                      : 'Aderência nas semanas completas: ${(adherence * 100).round()}%',
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Mês anterior',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () {
                        _month = DateTime.utc(_month.year, _month.month - 1);
                        _reload();
                      },
                    ),
                    Expanded(
                      child: Text(
                        monthLabel,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mês seguinte',
                      icon: const Icon(Icons.chevron_right),
                      onPressed:
                          monthStart.isBefore(DateTime.parse(widget.date)) &&
                              isoDay(
                                    DateTime.utc(_month.year, _month.month + 1),
                                  ).compareTo(widget.date) <=
                                  0
                          ? () {
                              _month = DateTime.utc(
                                _month.year,
                                _month.month + 1,
                              );
                              _reload();
                            }
                          : null,
                    ),
                  ],
                ),
                GridView.count(
                  crossAxisCount: 7,
                  mainAxisExtent:
                      MediaQuery.textScalerOf(context).scale(12) * 1.5 + 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 3,
                  crossAxisSpacing: 3,
                  children: [
                    for (final day in weekdays)
                      Semantics(
                        label: day,
                        excludeSemantics: true,
                        child: Center(
                          child: Text(
                            day.substring(0, 1),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    for (var i = 1; i < monthStart.weekday; i++)
                      const SizedBox.shrink(),
                    for (var i = 1; i <= daysInMonth; i++)
                      Center(
                        child: _DayChip(
                          label: '$i',
                          compact: true,
                          checked: days.contains(
                            isoDay(DateTime.utc(_month.year, _month.month, i)),
                          ),
                        ),
                      ),
                  ],
                ),
                Text('${days.length} realização(ões) no mês'),
                const SizedBox(height: 16),
                WeeklyHistory(history: habit.weeklyHistory),
                if (!habit.archived) ...[
                  const SizedBox(height: 18),
                  FilledButton.tonal(
                    onPressed: _archiving
                        ? null
                        : () async {
                            final changed = await Navigator.of(context)
                                .push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => HabitForm(
                                      bloc: widget.bloc,
                                      habit: habit,
                                    ),
                                  ),
                                );
                            if (changed == true && mounted) _reload();
                          },
                    child: const Text('Editar hábito'),
                  ),
                  TextButton(
                    onPressed: _archiving ? null : _archive,
                    child: const Text('Arquivar hábito'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}

class WeeklyHistory extends StatelessWidget {
  const WeeklyHistory({super.key, required this.history});
  final List<WeeklyProgress> history;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Frequência por semana',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      if (history.isEmpty) const Text('Nenhuma semana disponível.'),
      for (final week in history)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'Semana de ${displayDate(week.start)}: ${week.count} de ${week.target} dias'
            '${week.complete ? '' : ' · semana parcial'}',
          ),
        ),
    ],
  );
}

class RetryPanel extends StatelessWidget {
  const RetryPanel({super.key, required this.error, required this.retry});
  final Object? error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          error is ApiFailure
              ? (error as ApiFailure).message
              : 'Não foi possível carregar os dados.',
        ),
        TextButton(onPressed: retry, child: const Text('Tentar novamente')),
      ],
    ),
  );
}

class ArchivedPage extends StatefulWidget {
  const ArchivedPage({super.key, required this.bloc, required this.date});
  final HabitsBloc bloc;
  final String date;
  @override
  State<ArchivedPage> createState() => _ArchivedPageState();
}

class _ArchivedPageState extends State<ArchivedPage> {
  late Future<List<Habit>> _items = widget.bloc.repository.archived();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hábitos arquivados')),
    body: FutureBuilder(
      future: _items,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: RetryPanel(
              error: snapshot.error,
              retry: () => setState(() {
                _items = widget.bloc.repository.archived();
              }),
            ),
          );
        }
        final habits = snapshot.requireData;
        if (habits.isEmpty) {
          return const Center(child: Text('Nenhum hábito arquivado.'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final habit in habits)
              Card(
                child: ListTile(
                  title: Text(habit.name),
                  subtitle: const Text('Ver histórico, desarquivar ou excluir'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => HabitDetail(
                          bloc: widget.bloc,
                          habit: habit,
                          date: widget.date,
                        ),
                      ),
                    );
                    if (mounted) {
                      setState(() {
                        _items = widget.bloc.repository.archived();
                      });
                    }
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}
