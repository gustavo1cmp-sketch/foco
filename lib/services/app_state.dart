import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'native_bridge.dart';
import 'partner_service.dart';

/// Estado global: perfis, agendamentos, sessão ativa e fluxo de desbloqueio.
class AppState extends ChangeNotifier {
  AppState({this.firebaseOk = true});

  /// false quando o Firebase não está configurado (sem google-services.json).
  final bool firebaseOk;
  String? initError;
  final PartnerService partner = PartnerService();
  List<FocusProfile> profiles = [];
  List<Schedule> schedules = [];
  String? activeProfileId;
  DateTime? sessionEndsAt;
  int streak = 0;
  bool ready = false;

  late SharedPreferences _p;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    if (firebaseOk) {
      try {
        await partner.init();
      } catch (e) {
        initError = 'Parceiro indisponível: $e';
      }
    }
    final pr = _p.getString('profiles');
    final sc = _p.getString('schedules');
    profiles = pr == null
        ? [FocusProfile(id: 'default', name: 'Foco')]
        : decodeProfiles(pr);
    schedules = sc == null ? [] : decodeSchedules(sc);
    streak = _p.getInt('streak') ?? 0;
    final end = _p.getInt('sessionEnd');
    if (end != null && end > DateTime.now().millisecondsSinceEpoch) {
      sessionEndsAt = DateTime.fromMillisecondsSinceEpoch(end);
      activeProfileId = _p.getString('sessionProfile');
    }
    NativeBridge.onBlockedAttempt((t) => lastBlockedTarget.value = t);
    ready = true;
    try {
      await _push();
    } catch (_) {}
    notifyListeners();
  }

  /// Último app que o usuário tentou abrir bloqueado (a UI mostra a tela de pedido).
  final lastBlockedTarget = ValueNotifier<String?>(null);

  /// Permite que telas peçam atualização da UI após mudar o pareamento.
  void refresh() => notifyListeners();

  bool get paired => partner.role != PairRole.none;
  bool get sessionActive =>
      sessionEndsAt != null && sessionEndsAt!.isAfter(DateTime.now());

  // -------- sessão de foco --------

  Future<void> startSession(String profileId, Duration d) async {
    activeProfileId = profileId;
    sessionEndsAt = DateTime.now().add(d);
    await _p.setInt('sessionEnd', sessionEndsAt!.millisecondsSinceEpoch);
    await _p.setString('sessionProfile', profileId);
    await _push();
    notifyListeners();
  }

  /// Chamado só quando o tempo acaba normalmente OU o parceiro aprovou.
  Future<void> endSession({bool completed = false}) async {
    if (completed) {
      streak++;
      await _p.setInt('streak', streak);
    }
    sessionEndsAt = null;
    activeProfileId = null;
    await _p.remove('sessionEnd');
    await _p.remove('sessionProfile');
    await _push();
    notifyListeners();
  }

  // -------- edição de regras --------
  // Com parceiro pareado, qualquer edição que AFROUXE regras exige aprovação.
  // A UI chama requestUnlock(action: 'edit_rules') antes de permitir salvar.

  Future<void> saveProfile(FocusProfile p) async {
    final i = profiles.indexWhere((e) => e.id == p.id);
    i >= 0 ? profiles[i] = p : profiles.add(p);
    await _persist();
  }

  Future<void> saveSchedule(Schedule s) async {
    final i = schedules.indexWhere((e) => e.id == s.id);
    i >= 0 ? schedules[i] = s : schedules.add(s);
    await _persist();
  }

  Future<void> removeSchedule(String id) async {
    schedules.removeWhere((e) => e.id == id);
    await _persist();
  }

  Future<void> _persist() async {
    await _p.setString('profiles', encodeList(profiles));
    await _p.setString('schedules', encodeSchedules(schedules));
    await _push();
    notifyListeners();
  }

  Future<void> _push() => NativeBridge.syncRules(
        profiles: profiles,
        schedules: schedules,
        activeSessionProfileId: sessionActive ? activeProfileId : null,
        sessionEndsAtMillis: sessionEndsAt?.millisecondsSinceEpoch,
      );

  // -------- fluxo de desbloqueio pelo parceiro --------

  /// Pede liberação ao parceiro e aguarda a decisão. Retorna o pedido final.
  Future<UnlockRequest> askPartner({
    required String action,
    String? target,
    String reason = '',
  }) async {
    final id = await partner.requestUnlock(
        action: action, target: target, reason: reason);
    final completer = Completer<UnlockRequest>();
    late StreamSubscription sub;
    sub = partner.watchRequest(id).listen((r) async {
      if (r.status == 'approved' && r.grantedUntil != null) {
        await NativeBridge.grantTemporaryUnlock(
          target: target,
          untilMillis: r.grantedUntil!.millisecondsSinceEpoch,
        );
        if (action == 'end_session') await endSession();
        completer.complete(r);
        sub.cancel();
      } else if (r.status == 'denied') {
        completer.complete(r);
        sub.cancel();
      }
    });
    return completer.future.timeout(const Duration(minutes: 30), onTimeout: () {
      sub.cancel();
      throw TimeoutException('O parceiro não respondeu.');
    });
  }
}
