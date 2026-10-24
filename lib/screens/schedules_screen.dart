import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../services/app_state.dart';
import 'home_screen.dart' show showAskPartnerSheet;

class SchedulesScreen extends StatelessWidget {
  const SchedulesScreen({super.key});

  static const _days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _edit(context, null),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Text('Agendamentos', style: Theme.of(context).textTheme.headlineSmall),
        for (final sc in s.schedules)
          Card(
            child: SwitchListTile(
              title: Text('${_t(sc.startMinutes)} – ${_t(sc.endMinutes)}'),
              subtitle: Text(
                '${sc.weekdays.map((d) => _days[d - 1]).join(', ')}\n'
                'Perfil: ${_profileInfo(s, sc)}',
              ),
              isThreeLine: true,
              value: sc.enabled,
              onChanged: (v) async {
                // Desligar um agendamento é afrouxar a regra: exige parceiro.
                if (!v && s.paired) {
                  await showAskPartnerSheet(context, action: 'edit_rules');
                  return;
                }
                sc.enabled = v;
                await s.saveSchedule(sc);
              },
              secondary: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _edit(context, sc),
              ),
            ),
          ),
        if (s.schedules.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Nenhum agendamento ainda.')),
          ),
      ]),
    );
  }

  String _profileInfo(AppState s, Schedule sc) {
    final p = s.profiles.firstWhere((p) => p.id == sc.profileId,
        orElse: () => s.profiles.first);
    return '${p.name} (${p.blockedApps.length} apps bloqueados)';
  }

  String _t(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _edit(BuildContext context, Schedule? existing) async {
    final s = context.read<AppState>();
    final sc = existing ??
        Schedule(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          profileId: s.profiles.first.id,
          weekdays: [1, 2, 3, 4, 5, 6, 7],
          startMinutes: 9 * 60,
          endMinutes: 18 * 60,
        );
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, children: [
              for (var i = 1; i <= 7; i++)
                FilterChip(
                  label: Text(_days[i - 1]),
                  selected: sc.weekdays.contains(i),
                  onSelected: (v) => set(() {
                    final l = [...sc.weekdays];
                    v ? l.add(i) : l.remove(i);
                    sc.weekdays = l;
                  }),
                ),
            ]),
            ListTile(
              title: const Text('Início'),
              trailing: Text(_t(sc.startMinutes)),
              onTap: () async {
                final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay(
                        hour: sc.startMinutes ~/ 60, minute: sc.startMinutes % 60));
                if (t != null) set(() => sc.startMinutes = t.hour * 60 + t.minute);
              },
            ),
            ListTile(
              title: const Text('Fim'),
              trailing: Text(_t(sc.endMinutes)),
              onTap: () async {
                final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay(
                        hour: sc.endMinutes ~/ 60, minute: sc.endMinutes % 60));
                if (t != null) set(() => sc.endMinutes = t.hour * 60 + t.minute);
              },
            ),
            DropdownButton<String>(
              value: sc.profileId,
              isExpanded: true,
              items: [
                for (final p in s.profiles)
                  DropdownMenuItem(value: p.id, child: Text(p.name))
              ],
              onChanged: (v) => set(() => sc.profileId = v!),
            ),
            FilledButton(
              onPressed: () async {
                await s.saveSchedule(sc);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Salvar'),
            ),
          ]),
        ),
      ),
    );
  }
}
