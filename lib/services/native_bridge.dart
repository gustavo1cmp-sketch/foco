import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import '../models.dart';

/// Ponte para o código nativo (Kotlin no Android, Swift no iOS).
class NativeBridge {
  static const _ch = MethodChannel('foco/native');

  /// Android: lista de apps instalados {package, label}.
  static Future<List<Map<String, dynamic>>> installedApps() async {
    if (!Platform.isAndroid) return [];
    final r = await _ch.invokeListMethod<Map>('installedApps') ?? [];
    return r.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Retorna o estado das permissões necessárias.
  static Future<Map<String, bool>> permissions() async {
    final r = await _ch.invokeMapMethod<String, bool>('permissions');
    return r ?? {};
  }

  /// Abre a tela do sistema para conceder a permissão pedida.
  /// Android: accessibility | usage | overlay | deviceAdmin | notifications
  /// iOS: familyControls (abre o diálogo de autorização)
  static Future<void> requestPermission(String name) =>
      _ch.invokeMethod('requestPermission', {'name': name});

  /// iOS: abre o seletor nativo (FamilyActivityPicker) e devolve a seleção serializada.
  static Future<String?> pickAppsIOS(String profileId) =>
      _ch.invokeMethod<String>('pickApps', {'profileId': profileId});

  /// Envia as regras ativas ao motor nativo de bloqueio.
  static Future<void> syncRules({
    required List<FocusProfile> profiles,
    required List<Schedule> schedules,
    required String? activeSessionProfileId,
    required int? sessionEndsAtMillis,
  }) =>
      _ch.invokeMethod('syncRules', {
        'profiles': encodeList(profiles),
        'schedules': encodeSchedules(schedules),
        'activeSessionProfileId': activeSessionProfileId,
        'sessionEndsAt': sessionEndsAtMillis,
      });

  /// Concede liberação temporária (token do parceiro já validado).
  static Future<void> grantTemporaryUnlock({
    required String? target,
    required int untilMillis,
  }) =>
      _ch.invokeMethod('grantUnlock', {'target': target, 'until': untilMillis});

  /// Tempo de uso de hoje por app, em minutos.
  static Future<Map<String, int>> todayUsage() async {
    final r = await _ch.invokeMapMethod<String, int>('todayUsage');
    return r ?? {};
  }

  /// Tempo de uso dos últimos 7 dias (minutos totais por dia, mais antigo primeiro).
  static Future<List<int>> weeklyUsage() async {
    final r = await _ch.invokeListMethod<int>('weeklyUsage');
    return r ?? List.filled(7, 0);
  }

  /// Protege contra desinstalação (Android: Device Admin).
  static Future<void> setUninstallProtection(bool on) =>
      _ch.invokeMethod('setUninstallProtection', {'on': on});

  /// Eventos do nativo, ex.: usuário tentou abrir app bloqueado.
  static void onBlockedAttempt(void Function(String target) cb) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'blockedAttempt') cb(call.arguments as String);
    });
  }
}
