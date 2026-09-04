import SwiftUI

@main
struct GrabaAnalisisApp: App {

    @StateObject private var store = SessionStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var governor = MemoryGovernor.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppGroup.prepareDirectories()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(governor)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        // La extensión de difusión pudo dejar una sesión nueva
                        // mientras la app estaba en segundo plano.
                        store.adoptBroadcastSessionIfNeeded()
                        governor.sample()
                    }
                }
        }
    }
}
