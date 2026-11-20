import 'dart:async';

import 'habits_data.dart';

sealed class HabitsEvent {
  const HabitsEvent();
}

class HabitsRequested extends HabitsEvent {
  const HabitsRequested();
}

class HabitCheckInRequested extends HabitsEvent {
  const HabitCheckInRequested(this.id, {this.quantity, this.expectedDate});
  final int id;
  final int? quantity;
  final String? expectedDate;
}

class HabitUndoRequested extends HabitsEvent {
  const HabitUndoRequested(this.id, {this.expectedDate});
  final int id;
  final String? expectedDate;
}

class AvatarSelected extends HabitsEvent {
  const AvatarSelected(this.avatar);
  final String avatar;
}

class HabitSaveRequested extends HabitsEvent {
  HabitSaveRequested(this.fields, {this.id});
  final Json fields;
  final int? id;
  final result = Completer<String?>();
  bool outcomeUnknown = false;
}

class HabitArchiveRequested extends HabitsEvent {
  HabitArchiveRequested(this.id);
  final int id;
  final result = Completer<String?>();
}

class HabitRestoreRequested extends HabitsEvent {
  HabitRestoreRequested(this.id);
  final int id;
  final result = Completer<String?>();
}

class HabitDeleteRequested extends HabitsEvent {
  HabitDeleteRequested(this.id);
  final int id;
  final result = Completer<String?>();
}

class HabitsState {
  const HabitsState({
    this.dashboard,
    this.busy = false,
    this.pendingId,
    this.error,
    this.notice,
    this.reward,
  });
  final Dashboard? dashboard;
  final bool busy;
  final int? pendingId, reward;
  final String? error, notice;
}

class HabitsBloc {
  HabitsBloc(this.repository);
  final HabitRepository repository;
  final _states = StreamController<HabitsState>.broadcast();
  Stream<HabitsState> get states => _states.stream;
  HabitsState state = const HabitsState(busy: true);
  bool _running = false;
  bool _closed = false;
  bool _refreshQueued = false;

  void _emit(HabitsState next) {
    if (_closed) return;
    state = next;
    _states.add(next);
  }

  Future<void> add(HabitsEvent event) async {
    if (_closed || _running) {
      if (!_closed && event is HabitsRequested) _refreshQueued = true;
      if (event is HabitSaveRequested) {
        event.result.complete('Aguarde a operação em andamento.');
      }
      if (event is HabitArchiveRequested) {
        event.result.complete('Aguarde a operação em andamento.');
      }
      if (event is HabitRestoreRequested) {
        event.result.complete('Aguarde a operação em andamento.');
      }
      if (event is HabitDeleteRequested) {
        event.result.complete('Aguarde a operação em andamento.');
      }
      return;
    }
    _running = true;
    final previous = state.dashboard;
    _emit(
      HabitsState(
        dashboard: previous,
        busy: true,
        pendingId: switch (event) {
          HabitCheckInRequested(:final id) => id,
          HabitUndoRequested(:final id) => id,
          _ => null,
        },
      ),
    );
    int? reward;
    String? notice;
    String? actionError;
    try {
      switch (event) {
        case HabitsRequested():
          break;
        case HabitCheckInRequested(
          :final id,
          :final quantity,
          :final expectedDate,
        ):
          if (previous != null) {
            reward = await repository.checkInToday(
              id,
              expectedDate ?? previous.date,
              quantity: quantity,
            );
            if (reward == 0) notice = 'Progresso de hoje salvo.';
            if (reward < 0) {
              notice = 'Progresso corrigido. XP e conquistas atualizados.';
            }
          }
        case HabitUndoRequested(:final id, :final expectedDate):
          if (previous != null) {
            await repository.undoToday(id, expectedDate ?? previous.date);
            notice = 'Registro de hoje desfeito. XP e conquistas atualizados.';
          }
        case AvatarSelected(:final avatar):
          await repository.selectAvatar(avatar);
          notice = 'Avatar atualizado.';
        case HabitSaveRequested(:final id, :final fields):
          await repository.save(fields, id: id);
          notice = id == null ? 'Hábito criado!' : 'Alterações salvas.';
        case HabitArchiveRequested(:final id):
          await repository.archive(id);
          notice = 'Hábito arquivado.';
        case HabitRestoreRequested(:final id):
          await repository.restore(id);
          notice = 'Hábito restaurado para sua rotina.';
        case HabitDeleteRequested(:final id):
          await repository.delete(id);
          notice = 'Hábito e todos os seus dados excluídos.';
      }
      try {
        final dashboard = await repository.dashboard();
        _emit(
          HabitsState(dashboard: dashboard, reward: reward, notice: notice),
        );
      } on ApiFailure catch (failure) {
        _emit(
          HabitsState(
            dashboard: previous,
            reward: reward,
            notice: notice,
            error: failure.message,
          ),
        );
      }
    } on ApiFailure catch (failure) {
      if (event is HabitSaveRequested) {
        event.outcomeUnknown = failure.outcomeUnknown;
      }
      actionError = failure.message;
      _emit(HabitsState(dashboard: previous, error: failure.message));
      if (failure.code == 'day_changed') _refreshQueued = true;
    } finally {
      _running = false;
      if (event is HabitSaveRequested) event.result.complete(actionError);
      if (event is HabitArchiveRequested) event.result.complete(actionError);
      if (event is HabitRestoreRequested) event.result.complete(actionError);
      if (event is HabitDeleteRequested) event.result.complete(actionError);
      if (_refreshQueued && !_closed) {
        _refreshQueued = false;
        unawaited(add(const HabitsRequested()));
      }
    }
  }

  void close() {
    _closed = true;
    unawaited(_states.close());
  }
}
