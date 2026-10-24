import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../models.dart';

/// Papel deste aparelho no pareamento.
enum PairRole { none, owner, partner }

/// Parceiro de confiança.
///
/// Regra de ouro: a senha/autorização NUNCA fica no aparelho do dono.
/// O dono só cria pedidos; quem decide é o aparelho do parceiro, que valida
/// o PIN do app e/ou a biometria/senha de tela dele (local_auth).
/// O Firestore (ver firestore.rules) impede que o dono altere o status
/// de um pedido, apague o pareamento ou aprove a si mesmo.
class PartnerService {
  late final _db = FirebaseFirestore.instance;
  late final _auth = FirebaseAuth.instance;
  final _secure = const FlutterSecureStorage();
  late final _localAuth = LocalAuthentication();

  String? pairId;
  PairRole role = PairRole.none;

  String get uid => _auth.currentUser!.uid;

  Future<void> init() async {
    if (_auth.currentUser == null) await _auth.signInAnonymously();
    pairId = await _secure.read(key: 'pairId');
    final r = await _secure.read(key: 'role');
    role = PairRole.values.firstWhere((e) => e.name == r,
        orElse: () => PairRole.none);
    // Salva o token de push para o outro lado poder nos notificar.
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _db.collection('users').doc(uid).set({'fcmToken': token});
    }
  }

  // ---------------- Pareamento ----------------

  /// DONO: cria um convite. Retorna o texto para virar QR Code.
  Future<String> createInvite() async {
    final secret = _randomString(24);
    final ref = _db.collection('pairs').doc();
    await ref.set({
      'ownerUid': uid,
      'partnerUid': null,
      'joinSecret': secret,
      'createdAt': FieldValue.serverTimestamp(),
    });
    pairId = ref.id;
    role = PairRole.owner;
    await _secure.write(key: 'pairId', value: ref.id);
    await _secure.write(key: 'role', value: 'owner');
    return 'foco://pair/${ref.id}/$secret';
  }

  /// PARCEIRO: aceita o convite lido do QR. Define o PIN que só ele conhece.
  Future<void> acceptInvite(String payload, String partnerPin) async {
    final parts = Uri.parse(payload).pathSegments;
    final id = parts[0];
    final secret = parts[1];
    await _db.collection('pairs').doc(id).update({
      'partnerUid': uid,
      'joinSecret': secret, // a regra confere o segredo e só aceita 1x
    });
    pairId = id;
    role = PairRole.partner;
    await _secure.write(key: 'pairId', value: id);
    await _secure.write(key: 'role', value: 'partner');
    await _secure.write(key: 'partnerPin', value: partnerPin);
  }

  Future<bool> isPaired() async {
    if (pairId == null) return false;
    final d = await _db.collection('pairs').doc(pairId).get();
    return d.exists && d.data()?['partnerUid'] != null;
  }

  // ---------------- Lado do DONO ----------------

  /// Cria um pedido de desbloqueio. Retorna o id para acompanhar.
  Future<String> requestUnlock({
    required String action,
    String? target,
    String reason = '',
  }) async {
    // Limite diário de pedidos (anti-insistência), checado também nas regras.
    final start = DateTime.now().subtract(const Duration(hours: 24));
    final recent = await _db
        .collection('pairs/$pairId/requests')
        .where('createdAt', isGreaterThan: Timestamp.fromDate(start))
        .count()
        .get();
    if ((recent.count ?? 0) >= 10) {
      throw Exception('Limite de 10 pedidos por dia atingido.');
    }
    final ref = await _db.collection('pairs/$pairId/requests').add({
      'ownerUid': uid,
      'action': action,
      'target': target,
      'reason': reason,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// DONO: espera a decisão do parceiro.
  Stream<UnlockRequest> watchRequest(String id) => _db
      .doc('pairs/$pairId/requests/$id')
      .snapshots()
      .map((s) => _toRequest(s));

  // ---------------- Lado do PARCEIRO ----------------

  /// PARCEIRO: pedidos pendentes em tempo real.
  Stream<List<UnlockRequest>> pendingRequests() => _db
      .collection('pairs/$pairId/requests')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((q) => q.docs.map(_toRequest).toList());

  /// PARCEIRO: valida PIN do app + biometria/senha do aparelho dele.
  Future<bool> verifyPartner(String pinTyped) async {
    final pin = await _secure.read(key: 'partnerPin');
    if (pin == null || pin != pinTyped) return false;
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Confirme que é você para liberar o aplicativo',
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> decide(String requestId, {required bool approve, int minutes = 5}) {
    return _db.doc('pairs/$pairId/requests/$requestId').update({
      'status': approve ? 'approved' : 'denied',
      if (approve)
        'grantedUntil':
            Timestamp.fromDate(DateTime.now().add(Duration(minutes: minutes))),
      'decidedAt': FieldValue.serverTimestamp(),
    });
  }

  /// PARCEIRO: encerra o pareamento (só ele pode).
  Future<void> unpair() async {
    await _db.doc('pairs/$pairId').delete();
    await _secure.delete(key: 'pairId');
    await _secure.delete(key: 'role');
    pairId = null;
    role = PairRole.none;
  }

  // ---------------- util ----------------

  UnlockRequest _toRequest(DocumentSnapshot s) {
    final d = s.data() as Map<String, dynamic>;
    var status = d['status'] as String;
    final until = (d['grantedUntil'] as Timestamp?)?.toDate();
    if (status == 'approved' && until != null && until.isBefore(DateTime.now())) {
      status = 'expired';
    }
    return UnlockRequest(
      id: s.id,
      action: d['action'],
      target: d['target'],
      reason: d['reason'] ?? '',
      status: status,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      grantedUntil: until,
    );
  }

  String _randomString(int n) {
    const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
