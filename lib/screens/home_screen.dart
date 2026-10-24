import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../services/app_state.dart';
import '../services/native_bridge.dart';
import 'partner_screen.dart';
import 'profiles_screen.dart';
import 'schedules_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = context.read<AppState>();
      if (s.sessionEndsAt != null && !s.sessionActive) {
        s.endSession(completed: true);
      }
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().lastBlockedTarget.addListener(_onBlocked);
    });
  }

  void _onBlocked() {
    final t = context.read<AppState>().lastBlockedTarget.value;
    if (t == null || !mounted) return;
    showAskPartnerSheet(context, action: 'open_app', target: t);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _FocusTab(),
      const SchedulesScreen(),
      const StatsScreen(),
      const PartnerScreen(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bolt), label: 'Foco'),
          NavigationDestination(icon: Icon(Icons.schedule), label: 'Agenda'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Uso'),
          NavigationDestination(icon: Icon(Icons.shield), label: 'Parceiro'),
        ],
      ),
    );
  }
}

class _FocusTab extends StatelessWidget {
  const _FocusTab();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final left = s.sessionActive ? s.sessionEndsAt!.difference(DateTime.now()) : null;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _PermissionBanner(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(s.sessionActive ? 'Sessão em andamento' : 'Pronto para focar?',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(
                left == null ? '--:--' : _fmt(left),
                style: Theme.of(context)
                    .textTheme
                    .displayLarge
                    ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 8),
              Text('🔥 ${s.streak} sessões concluídas'),
              const SizedBox(height: 16),
              if (!s.sessionActive)
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar sessão'),
                  onPressed: () => _startDialog(context),
                )
              else
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: Text(s.paired ? 'Pedir ao parceiro para encerrar' : 'Encerrar'),
                  onPressed: () => s.paired
                      ? showAskPartnerSheet(context, action: 'end_session')
                      : s.endSession(),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('Perfis de foco'),
          subtitle: Text(s.profiles.map((e) => e.name).join(' · ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ProfilesScreen())),
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, sec = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  Future<void> _startDialog(BuildContext context) async {
    final s = context.read<AppState>();
    String profileId = s.profiles.first.id;
    int minutes = 25;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nova sessão'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String>(
              value: profileId,
              isExpanded: true,
              items: [
                for (final p in s.profiles)
                  DropdownMenuItem(value: p.id, child: Text(p.name))
              ],
              onChanged: (v) => set(() => profileId = v!),
            ),
            Slider(
              value: minutes.toDouble(),
              min: 5,
              max: 240,
              divisions: 47,
              label: '$minutes min',
              onChanged: (v) => set(() => minutes = v.round()),
            ),
            Text('$minutes minutos'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                s.startSession(profileId, Duration(minutes: minutes));
                Navigator.pop(ctx);
              },
              child: const Text('Começar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, bool>>(
      future: NativeBridge.permissions(),
      builder: (context, snap) {
        final missing = (snap.data ?? {}).entries.where((e) => !e.value).toList();
        if (missing.isEmpty) return const SizedBox.shrink();
        return Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Column(children: [
            const ListTile(
              leading: Icon(Icons.warning_amber),
              title: Text('Permissões necessárias para o bloqueio funcionar'),
            ),
            for (final m in missing)
              ListTile(
                dense: true,
                title: Text(_label(m.key)),
                trailing: TextButton(
                  onPressed: () => NativeBridge.requestPermission(m.key),
                  child: const Text('Conceder'),
                ),
              ),
          ]),
        );
      },
    );
  }

  String _label(String k) => switch (k) {
        'accessibility' => 'Serviço de acessibilidade (detecta app aberto)',
        'usage' => 'Acesso ao uso de apps (estatísticas e limites)',
        'overlay' => 'Exibir sobre outros apps (tela de bloqueio)',
        'deviceAdmin' => 'Administrador do dispositivo (anti-desinstalação)',
        'notifications' => 'Notificações',
        'familyControls' => 'Tempo de Uso / Controles Parentais (iOS)',
        _ => k,
      };
}

/// Folha para pedir liberação ao parceiro.
Future<void> showAskPartnerSheet(BuildContext context,
    {required String action, String? target}) async {
  final s = context.read<AppState>();
  final reason = TextEditingController();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          s.paired ? 'Pedir liberação ao parceiro' : 'Sem parceiro pareado',
          style: Theme.of(ctx).textTheme.titleLarge,
        ),
        if (target != null) Text('App: $target'),
        const SizedBox(height: 12),
        if (s.paired) ...[
          TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(const SnackBar(
                  content: Text('Pedido enviado. Aguardando o parceiro...')));
              try {
                final r = await s.askPartner(
                    action: action, target: target, reason: reason.text);
                messenger.showSnackBar(SnackBar(
                    content: Text(r.status == 'approved'
                        ? 'Liberado pelo parceiro!'
                        : 'O parceiro negou o pedido.')));
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('Enviar pedido'),
          ),
        ] else
          const Text('Pareie um parceiro na aba "Parceiro" para ativar esta proteção.'),
      ]),
    ),
  );
}
