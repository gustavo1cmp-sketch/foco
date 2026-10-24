import DeviceActivity
import ManagedSettings
import FamilyControls

/// Extensão "Device Activity Monitor" (novo target no Xcode).
/// Roda em segundo plano para ligar/desligar o bloqueio nos horários agendados.
class FocoMonitor: DeviceActivityMonitor {
    private let defaults = UserDefaults(suiteName: "group.com.foco.app")!
    private let store = ManagedSettingsStore()

    private func shieldAll(profileIds: [String]) {
        var apps = Set<ApplicationToken>()
        var cats = Set<ActivityCategoryToken>()
        for id in profileIds {
            if let data = defaults.data(forKey: "selection_\(id)"),
               let sel = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) {
                apps.formUnion(sel.applicationTokens)
                cats.formUnion(sel.categoryTokens)
            }
        }
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = cats.isEmpty ? nil : .specific(cats)
    }

    private func profileId(from activity: DeviceActivityName) -> String? {
        // nomes: "sched_<scheduleId>_<dia>"  → procura o perfil do agendamento
        let parts = activity.rawValue.split(separator: "_")
        guard parts.count >= 3, parts[0] == "sched",
              let json = defaults.string(forKey: "schedules"),
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let sid = parts[1...(parts.count - 2)].joined(separator: "_")
        return arr.first { ($0["id"] as? String) == sid }?["profileId"] as? String
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        if let pid = profileId(from: activity) { shieldAll(profileIds: [pid]) }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        switch activity.rawValue {
        case "session":
            store.shield.applications = nil
            store.shield.applicationCategories = nil
        case "unlock":
            // Liberação do parceiro expirou: bloqueia de novo se ainda houver sessão/agenda.
            if let active = defaults.string(forKey: "activeProfile"),
               defaults.double(forKey: "endsAt") > Date().timeIntervalSince1970 * 1000 {
                shieldAll(profileIds: [active])
            }
        default:
            if profileId(from: activity) != nil {
                store.shield.applications = nil
                store.shield.applicationCategories = nil
            }
        }
    }
}
