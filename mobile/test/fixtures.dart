import 'package:habitquest/habits_data.dart';

Json habitFixture() => {
  'id': 1,
  'name': 'Leitura',
  'description': 'Antes de dormir',
  'icon': 'book',
  'color': 'violet',
  'weekly_target': 3,
  'weekly_count': 4,
  'streak': 2,
  'completed_today': true,
  'archived_at': null,
  'adherence': 1.0,
  'week_days': ['2026-11-16', '2026-11-17', '2026-11-18', '2026-11-19'],
  'weekly_history': [
    {
      'week_start': '2026-11-09',
      'weekly_count': 0,
      'weekly_target': 3,
      'complete_week': true,
    },
    {
      'week_start': '2026-11-16',
      'weekly_count': 4,
      'weekly_target': 3,
      'complete_week': false,
    },
  ],
};

Json dashboardFixture([List<Json>? habits]) => {
  'local_date': '2026-11-19',
  'week_start': '2026-11-16',
  'total_xp': 90,
  'level': 1,
  'habits': habits ?? [habitFixture()],
  'achievements': [],
};
