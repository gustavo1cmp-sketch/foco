import Flutter
import UIKit
import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity

/// Compartilhado com a extensão DeviceActivityMonitor via App Group.
enum Shared {
    static let group = "group.com.foco.app"
    static var defaults: UserDefaults { UserDefaults(suiteName: group)! }
    static let store = ManagedSettingsStore()

    static func applyShield(for profileIds: Set<String>) {
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

    static func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }
}

public class FocoPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel!
    private var pickerResult: FlutterResult?
    private var pickerSelection = FamilyActivitySelection()
    private var pendingProfileForPicker: String = "default"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let ch = FlutterMethodChannel(name: "foco/native", binaryMessenger: registrar.messenger())
        let inst = FocoPlugin()
        inst.channel = ch
        registrar.addMethodCallDelegate(inst, channel: ch)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "permissions":
            let ok = AuthorizationCenter.shared.authorizationStatus == .approved
            result(["familyControls": ok])

        case "requestPermission":
            Task {
                // .individual: o próprio usuário autoriza; a remoção do controle exige
                // o Face ID/senha dele, por isso o "parceiro" também deve guardar o código de Tempo de Uso (ver README).
                try? await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                result(nil)
            }

        case "pickApps":
            let args = call.arguments as? [String: Any]
            pendingProfileForPicker = args?["profileId"] as? String ?? "default"
            pickerSelection = FamilyActivitySelection()
            if let data = Shared.defaults.data(forKey: "selection_\(pendingProfileForPicker)"),
               let old = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) {
                pickerSelection = old
            }
            presentPicker(result: result)

        case "syncRules":
            guard let args = call.arguments as? [String: Any] else { return result(nil) }
            Shared.defaults.set(args["profiles"] as? String, forKey: "profiles")
            Shared.defaults.set(args["schedules"] as? String, forKey: "schedules")
            let active = args["activeSessionProfileId"] as? String
            let ends = (args["sessionEndsAt"] as? NSNumber)?.doubleValue ?? 0
            Shared.defaults.set(active, forKey: "activeProfile")
            Shared.defaults.set(ends, forKey: "endsAt")
            if let active = active, ends > Date().timeIntervalSince1970 * 1000 {
                Shared.applyShield(for: [active])
                scheduleEnd(of: ends)
            } else {
                Shared.clearShield()
            }
            registerSchedules(json: args["schedules"] as? String ?? "[]")
            result(nil)

        case "grantUnlock":
            guard let args = call.arguments as? [String: Any],
                  let until = (args["until"] as? NSNumber)?.doubleValue else { return result(nil) }
            Shared.clearShield()
            Shared.defaults.set(until, forKey: "unlockUntil")
            // Quando a liberação expira, a extensão reaplica o bloqueio.
            let end = Date(timeIntervalSince1970: until / 1000)
            let cal = Calendar.current
            let schedule = DeviceActivitySchedule(
                intervalStart: cal.dateComponents([.hour, .minute, .second], from: Date()),
                intervalEnd: cal.dateComponents([.hour, .minute, .second], from: end),
                repeats: false)
            try? DeviceActivityCenter().startMonitoring(DeviceActivityName("unlock"), during: schedule)
            result(nil)

        // iOS não entrega uso por app ao app principal (só via DeviceActivityReport).
        case "todayUsage": result([String: Int]())
        case "weeklyUsage": result([Int](repeating: 0, count: 7))
        case "installedApps": result([])
        case "setUninstallProtection": result(nil)
        default: result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Seletor nativo de apps

    private func presentPicker(result: @escaping FlutterResult) {
        pickerResult = result
        let view = PickerView(selection: Binding(
            get: { self.pickerSelection },
            set: { self.pickerSelection = $0 }
        )) { [weak self] in
            guard let self = self else { return }
            let id = self.pendingProfileForPicker
            if let data = try? PropertyListEncoder().encode(self.pickerSelection) {
                Shared.defaults.set(data, forKey: "selection_\(id)")
            }
            UIApplication.shared.keyWindow?.rootViewController?.dismiss(animated: true)
            self.pickerResult?("selection_\(id)")
            self.pickerResult = nil
        }
        let host = UIHostingController(rootView: view)
        UIApplication.shared.keyWindow?.rootViewController?.present(host, animated: true)
    }

    // MARK: - Agendamentos (executados pela extensão DeviceActivityMonitor)

    private func registerSchedules(json: String) {
        let center = DeviceActivityCenter()
        center.stopMonitoring()
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        for sc in arr where (sc["enabled"] as? Bool ?? true) {
            guard let id = sc["id"] as? String,
                  let s = sc["startMinutes"] as? Int, let e = sc["endMinutes"] as? Int,
                  let days = sc["weekdays"] as? [Int] else { continue }
            for d in days {
                let weekday = (d % 7) + 1 // 1=domingo no Calendar
                let schedule = DeviceActivitySchedule(
                    intervalStart: DateComponents(hour: s / 60, minute: s % 60, weekday: weekday),
                    intervalEnd: DateComponents(hour: e / 60, minute: e % 60, weekday: weekday),
                    repeats: true)
                try? center.startMonitoring(DeviceActivityName("sched_\(id)_\(d)"), during: schedule)
            }
        }
    }

    private func scheduleEnd(of endMillis: Double) {
        let end = Date(timeIntervalSince1970: endMillis / 1000)
        let cal = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.hour, .minute, .second], from: Date()),
            intervalEnd: cal.dateComponents([.hour, .minute, .second], from: end),
            repeats: false)
        try? DeviceActivityCenter().startMonitoring(DeviceActivityName("session"), during: schedule)
    }
}

struct PickerView: View {
    @Binding var selection: FamilyActivitySelection
    var onDone: () -> Void
    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle("Apps bloqueados")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK", action: onDone) } }
        }
    }
}
