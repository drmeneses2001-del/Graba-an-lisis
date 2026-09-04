import SwiftUI

struct RootView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            RecordView()
                .tabItem { Label("Grabar", systemImage: "waveform.circle.fill") }
                .tag(0)

            SessionsView()
                .tabItem { Label("Sesiones", systemImage: "list.bullet.rectangle") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(2)
        }
    }
}
