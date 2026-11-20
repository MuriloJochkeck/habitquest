import 'package:flutter/material.dart';

import 'habits_data.dart';

const avatarOptions = {
  'compass': (Icons.explore_rounded, 'Explorador'),
  'leaf': (Icons.eco_rounded, 'Guardião'),
  'flame': (Icons.local_fire_department_rounded, 'Determinado'),
};

class JourneyCard extends StatelessWidget {
  const JourneyCard({super.key, required this.data, this.onAvatar});
  final Dashboard data;
  final ValueChanged<String>? onAvatar;

  @override
  Widget build(BuildContext context) {
    final avatar = avatarOptions[data.avatar] ?? avatarOptions['compass']!;
    final rank = data.level >= 10
        ? 'Lenda da constância'
        : data.level >= 5
        ? 'Aventureiro'
        : 'Aprendiz';
    return Card(
      elevation: 0,
      color: const Color(0xffeee8fc),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xff6d28d9),
                  child: Icon(avatar.$1, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        avatar.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('$rank · Nível ${data.level}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Seu avatar',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in avatarOptions.entries)
                  ChoiceChip(
                    avatar: Icon(entry.value.$1, size: 18),
                    label: Text(entry.value.$2),
                    selected: entry.key == data.avatar,
                    onSelected: onAvatar == null
                        ? null
                        : (selected) {
                            if (selected) onAvatar!(entry.key);
                          },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Marcos da jornada',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final milestone in [
                  (1, 'Primeiro passo'),
                  (5, 'Aventureiro'),
                  (10, 'Lenda'),
                ])
                  Chip(
                    avatar: Icon(
                      data.level >= milestone.$1
                          ? Icons.workspace_premium
                          : Icons.lock_outline,
                      color: data.level >= milestone.$1
                          ? const Color(0xff92400e)
                          : null,
                      size: 20,
                    ),
                    label: Text('${milestone.$2} · Nv. ${milestone.$1}'),
                  ),
              ],
            ),
            Text(
              data.level < 5
                  ? 'Próximo título no nível 5.'
                  : data.level < 10
                  ? 'Próximo título no nível 10.'
                  : 'Você conquistou todos os títulos desta jornada.',
            ),
          ],
        ),
      ),
    );
  }
}

class WeeklySummaryCard extends StatelessWidget {
  const WeeklySummaryCard({super.key, required this.summary});
  final WeeklySummary summary;
  String _date(String value) => value.split('-').reversed.join('/');

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: const Color(0xffe1faef),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sua semana em perspectiva',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${summary.current} realizações · ${summary.delta > 0 ? '+' : ''}${summary.delta} em relação ao mesmo período anterior',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Atual: ${_date(summary.currentStart)} a ${_date(summary.currentEnd)}',
          ),
          Text(
            'Anterior: ${_date(summary.previousStart)} a ${_date(summary.previousEnd)} · ${summary.previous} realizações',
          ),
          const SizedBox(height: 8),
          Text(
            summary.bestHabit == null
                ? 'Conclua uma missão para ter seu primeiro destaque.'
                : 'Destaque da semana: ${summary.bestHabit}',
          ),
          const Text(
            'O resumo conta dias com a meta diária concluída, incluindo hábitos arquivados.',
          ),
        ],
      ),
    ),
  );
}
