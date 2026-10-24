import 'dart:convert';

/// Perfil de foco: conjunto de apps bloqueados + regras.
class FocusProfile {
  final String id;
  String name;
  List<String> blockedApps; // Android: package name | iOS: token serializado
  bool strictMode; // sem escapatória: só o parceiro libera
  Map<String, int> dailyLimitMinutes; // limite diário por app
  double? lat;
  double? lng;
  double radiusMeters; // bloqueio por localização (0 = desligado)

  FocusProfile({
    required this.id,
    required this.name,
    this.blockedApps = const [],
    this.strictMode = true,
    this.dailyLimitMinutes = const {},
    this.lat,
    this.lng,
    this.radiusMeters = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'blockedApps': blockedApps,
        'strictMode': strictMode,
        'dailyLimitMinutes': dailyLimitMinutes,
        'lat': lat,
        'lng': lng,
        'radiusMeters': radiusMeters,
      };

  factory FocusProfile.fromJson(Map<String, dynamic> j) => FocusProfile(
        id: j['id'],
        name: j['name'],
        blockedApps: List<String>.from(j['blockedApps'] ?? []),
        strictMode: j['strictMode'] ?? true,
        dailyLimitMinutes: Map<String, int>.from(j['dailyLimitMinutes'] ?? {}),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        radiusMeters: (j['radiusMeters'] as num?)?.toDouble() ?? 0,
      );
}

/// Agendamento recorrente.
class Schedule {
  final String id;
  String profileId;
  List<int> weekdays; // 1=segunda ... 7=domingo
  int startMinutes; // minutos desde 00:00
  int endMinutes;
  bool enabled;

  Schedule({
    required this.id,
    required this.profileId,
    required this.weekdays,
    required this.startMinutes,
    required this.endMinutes,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'weekdays': weekdays,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'enabled': enabled,
      };

  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
        id: j['id'],
        profileId: j['profileId'],
        weekdays: List<int>.from(j['weekdays']),
        startMinutes: j['startMinutes'],
        endMinutes: j['endMinutes'],
        enabled: j['enabled'] ?? true,
      );
}

/// Pedido de desbloqueio enviado ao parceiro.
class UnlockRequest {
  final String id;
  final String action; // open_app | end_session | disable | edit_rules | uninstall
  final String? target; // app alvo
  final String reason;
  final String status; // pending | approved | denied | expired
  final DateTime createdAt;
  final DateTime? grantedUntil;

  UnlockRequest({
    required this.id,
    required this.action,
    required this.target,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.grantedUntil,
  });
}

String encodeList(List<FocusProfile> l) =>
    jsonEncode(l.map((e) => e.toJson()).toList());
List<FocusProfile> decodeProfiles(String s) =>
    (jsonDecode(s) as List).map((e) => FocusProfile.fromJson(e)).toList();
String encodeSchedules(List<Schedule> l) =>
    jsonEncode(l.map((e) => e.toJson()).toList());
List<Schedule> decodeSchedules(String s) =>
    (jsonDecode(s) as List).map((e) => Schedule.fromJson(e)).toList();
