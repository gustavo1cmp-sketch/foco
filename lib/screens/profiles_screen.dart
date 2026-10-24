import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../services/app_state.dart';
import '../services/native_bridge.dart';
import 'home_screen.dart' show showAskPartnerSheet;

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Perfis de foco')),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileEditor(
              profile: FocusProfile(
                  id: DateTime.now().millisecondsSinceEpoch.toString(), name: 'Novo perfil'),
            ),
          ),
        ),
      ),
      body: ListView(children: [
        for (final p in s.profiles)
          ListTile(
            title: Text(p.name),
            subtitle: Text('${p.blockedApps.length} apps'
                '${p.strictMode ? ' · modo rígido' : ''}'
                '${p.radiusMeters > 0 ? ' · por local' : ''}'),
            onTap: () async {
              // Com parceiro, editar um perfil exige aprovação.
              if (s.paired && s.sessionActive) {
                await showAskPartnerSheet(context, action: 'edit_rules');
                return;
              }
              if (context.mounted) {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ProfileEditor(profile: p)));
              }
            },
          ),
      ]),
    );
  }
}

class ProfileEditor extends StatefulWidget {
  final FocusProfile profile;
  const ProfileEditor({super.key, required this.profile});
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late FocusProfile p = widget.profile;
  List<Map<String, String>> apps = [];

  @override
  void initState() {
    super.initState();
    NativeBridge.installedApps().then((v) => setState(() => apps = v));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil'), actions: [
        TextButton(
          onPressed: () async {
            await s.saveProfile(p);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Salvar'),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextFormField(
          initialValue: p.name,
          decoration: const InputDecoration(labelText: 'Nome'),
          onChanged: (v) => p.name = v,
        ),
        SwitchListTile(
          title: const Text('Modo rígido'),
          subtitle: const Text('Sem escapatória: só o parceiro libera durante a sessão.'),
          value: p.strictMode,
          onChanged: (v) => setState(() => p.strictMode = v),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.place),
          title: const Text('Bloquear por localização'),
          subtitle: Text(p.radiusMeters > 0
              ? 'Raio de ${p.radiusMeters.round()} m'
              : 'Desligado'),
          trailing: TextButton(
            child: const Text('Usar local atual'),
            onPressed: () async {
              await Geolocator.requestPermission();
              final pos = await Geolocator.getCurrentPosition();
              setState(() {
                p.lat = pos.latitude;
                p.lng = pos.longitude;
                p.radiusMeters = 150;
              });
            },
          ),
        ),
        if (p.radiusMeters > 0)
          Slider(
            value: p.radiusMeters,
            min: 50,
            max: 1000,
            label: '${p.radiusMeters.round()} m',
            onChanged: (v) => setState(() => p.radiusMeters = v),
          ),
        const Divider(),
        const Text('Apps bloqueados'),
        if (Platform.isIOS)
          ListTile(
            title: const Text('Escolher apps (seletor do iOS)'),
            subtitle: Text(p.blockedApps.isEmpty ? 'Nenhum' : 'Seleção salva'),
            onTap: () async {
              final sel = await NativeBridge.pickAppsIOS(p.id);
              if (sel != null) setState(() => p.blockedApps = [sel]);
            },
          )
        else
          for (final a in apps)
            CheckboxListTile(
              title: Text(a['label'] ?? a['package']!),
              subtitle: Text(a['package']!),
              value: p.blockedApps.contains(a['package']),
              secondary: p.blockedApps.contains(a['package'])
                  ? SizedBox(
                      width: 90,
                      child: TextFormField(
                        initialValue:
                            (p.dailyLimitMinutes[a['package']] ?? 0).toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(suffixText: 'min/dia'),
                        onChanged: (v) => p.dailyLimitMinutes = {
                          ...p.dailyLimitMinutes,
                          a['package']!: int.tryParse(v) ?? 0,
                        },
                      ),
                    )
                  : null,
              onChanged: (v) => setState(() {
                final l = [...p.blockedApps];
                v! ? l.add(a['package']!) : l.remove(a['package']);
                p.blockedApps = l;
              }),
            ),
      ]),
    );
  }
}
