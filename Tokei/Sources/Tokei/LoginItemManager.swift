import Combine
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    private init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ shouldEnable: Bool) {
        errorMessage = nil
        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
