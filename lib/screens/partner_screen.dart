import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models.dart';
import '../services/app_state.dart';
import '../services/partner_service.dart';

class PartnerScreen extends StatefulWidget {
  const PartnerScreen({super.key});
  @override
  State<PartnerScreen> createState() => _PartnerScreenState();
}

class _PartnerScreenState extends State<PartnerScreen> {
  String? _invite;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final role = s.partner.role;

    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Parceiro de confiança', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text(
        'A senha e a permissão de desbloqueio ficam no celular de outra pessoa. '
        'Você só consegue liberar apps, encerrar sessões ou mudar regras se ela aprovar.',
      ),
      const SizedBox(height: 20),
      if (!s.firebaseOk || s.initError != null)
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(!s.firebaseOk
                ? 'O Firebase ainda não foi configurado neste app (falta o google-services.json). '
                    'O bloqueio de apps funciona, mas o Parceiro de confiança só será ativado depois dessa configuração.'
                : '${s.initError}'),
          ),
        )
      else if (role == PairRole.none) ...[
        FilledButton.icon(
          icon: const Icon(Icons.qr_code),
          label: const Text('Convidar um parceiro (mostrar QR)'),
          onPressed: () async {
            final code = await s.partner.createInvite();
            setState(() => _invite = code);
            s.refresh();
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Sou o parceiro: escanear convite'),
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const _ScanScreen())),
        ),
      ],
      if (role == PairRole.owner) ...[
        if (_invite != null)
          Center(
            child: Column(children: [
              const Text('Peça para o parceiro escanear este QR no celular dele:'),
              const SizedBox(height: 12),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: _invite!, size: 220),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        FutureBuilder<bool>(
          future: s.partner.isPaired(),
          builder: (_, snap) => ListTile(
            leading: Icon(snap.data == true ? Icons.verified_user : Icons.hourglass_empty),
            title: Text(snap.data == true
                ? 'Parceiro pareado'
                : 'Aguardando o parceiro aceitar o convite'),
            subtitle: const Text('Só o parceiro pode desfazer o pareamento.'),
          ),
        ),
      ],
      if (role == PairRole.partner) const _PartnerInbox(),
    ]);
  }
}

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();
  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear convite')),
      body: MobileScanner(onDetect: (cap) async {
        final raw = cap.barcodes.first.rawValue;
        if (_handled || raw == null || !raw.startsWith('foco://pair/')) return;
        _handled = true;
        final s = context.read<AppState>();
        final pin = await _askPin(context);
        if (pin == null) {
          _handled = false;
          return;
        }
        try {
          await s.partner.acceptInvite(raw, pin);
          s.refresh();
          if (context.mounted) Navigator.pop(context);
        } catch (e) {
          _handled = false;
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Convite inválido: $e')));
          }
        }
      }),
    );
  }

  Future<String?> _askPin(BuildContext context) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crie seu PIN de parceiro'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Este PIN fica só no seu celular. Quem você está ajudando nunca o verá.'),
          TextField(
            controller: c,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => c.text.length >= 4 ? Navigator.pop(ctx, c.text) : null,
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}

/// Caixa de entrada do parceiro: aprova ou nega pedidos.
class _PartnerInbox extends StatelessWidget {
  const _PartnerInbox();

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return StreamBuilder<List<UnlockRequest>>(
      stream: s.partner.pendingRequests(),
      builder: (context, snap) {
        final list = snap.data ?? [];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const ListTile(
            leading: Icon(Icons.shield),
            title: Text('Você é o parceiro de confiança'),
          ),
          for (final r in list)
            Card(
              child: ListTile(
                title: Text(_actionLabel(r)),
                subtitle: Text(
                    '${r.reason.isEmpty ? 'Sem motivo informado' : r.reason}\n${r.createdAt}'),
                isThreeLine: true,
                trailing: r.status == 'pending'
                    ? const Icon(Icons.pending_actions)
                    : Text(r.status),
                onTap: r.status == 'pending' ? () => _review(context, r) : null,
              ),
            ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => s.partner.unpair().then((_) => s.refresh()),
            child: const Text('Encerrar pareamento'),
          ),
        ]);
      },
    );
  }

  String _actionLabel(UnlockRequest r) => switch (r.action) {
        'open_app' => 'Abrir ${r.target ?? 'app'}',
        'end_session' => 'Encerrar sessão de foco',
        'disable' => 'Desativar bloqueio',
        'edit_rules' => 'Alterar regras',
        'uninstall' => 'Desinstalar o app',
        _ => r.action,
      };

  Future<void> _review(BuildContext context, UnlockRequest r) async {
    final s = context.read<AppState>();
    final pin = TextEditingController();
    int minutes = 5;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(_actionLabel(r)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(r.reason.isEmpty ? 'Sem motivo informado.' : r.reason),
            const SizedBox(height: 12),
            DropdownButton<int>(
              value: minutes,
              items: const [
                DropdownMenuItem(value: 5, child: Text('Liberar por 5 min')),
                DropdownMenuItem(value: 30, child: Text('Liberar por 30 min')),
                DropdownMenuItem(value: 120, child: Text('Liberar por 2 h')),
                DropdownMenuItem(value: 720, child: Text('Liberar por 12 h')),
              ],
              onChanged: (v) => set(() => minutes = v!),
            ),
            TextField(
              controller: pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Seu PIN de parceiro'),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                await s.partner.decide(r.id, approve: false);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Negar'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await s.partner.verifyPartner(pin.text);
                if (!ok) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('PIN ou biometria incorretos.')));
                  }
                  return;
                }
                await s.partner.decide(r.id, approve: true, minutes: minutes);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Aprovar'),
            ),
          ],
        ),
      ),
    );
  }
}
