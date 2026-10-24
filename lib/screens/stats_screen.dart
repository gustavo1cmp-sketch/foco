import 'package:flutter/material.dart';
import '../services/native_bridge.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Tempo de tela', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      FutureBuilder<List<int>>(
        future: NativeBridge.weeklyUsage(),
        builder: (_, snap) {
          final data = snap.data ?? List.filled(7, 0);
          final maxV = data.reduce((a, b) => a > b ? a : b).clamp(1, 100000);
          const days = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
          final today = DateTime.now().weekday % 7; // domingo=0
          return SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < data.length; i++)
                  Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('${data[i] ~/ 60}h', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Container(
                      width: 24,
                      height: 100 * data[i] / maxV + 2,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(days[(today - (data.length - 1 - i)) % 7 < 0
                        ? 0
                        : (today - (data.length - 1 - i)) % 7]),
                  ]),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 24),
      Text('Hoje, por app', style: Theme.of(context).textTheme.titleMedium),
      FutureBuilder<Map<String, int>>(
        future: NativeBridge.todayUsage(),
        builder: (_, snap) {
          final e = (snap.data ?? {}).entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          if (e.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sem dados. Conceda a permissão de acesso ao uso.'),
            );
          }
          return Column(children: [
            for (final x in e.take(15))
              ListTile(title: Text(x.key), trailing: Text('${x.value} min')),
          ]);
        },
      ),
    ]);
  }
}
