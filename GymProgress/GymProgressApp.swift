import LocalAuthentication
import SwiftData
import SwiftUI

@main
struct GymProgressApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: ProgressPhoto.self)
    }
}

struct RootView: View {
    @AppStorage("faceIDLock") private var lockEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked = false
    @State private var authenticating = false

    var body: some View {
        ContentView()
            .overlay {
                // Also covers the app switcher snapshot while inactive.
                if lockEnabled && (!unlocked || scenePhase != .active) {
                    LockScreen(unlock: authenticate)
                }
            }
            .onAppear {
                if lockEnabled { authenticate() }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: unlocked = false
                case .active where lockEnabled && !unlocked: authenticate()
                default: break
                }
            }
            .onChange(of: lockEnabled) { _, enabled in
                if enabled { unlocked = true }
            }
    }

    private func authenticate() {
        guard !authenticating else { return }
        authenticating = true
        LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your progress photos") { success, _ in
            DispatchQueue.main.async {
                authenticating = false
                if success { unlocked = true }
            }
        }
    }
}

struct LockScreen: View {
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.largeTitle)
                Text("Progress photos are locked").font(.headline)
                Button("Unlock", action: unlock).buttonStyle(.borderedProminent)
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Timeline", systemImage: "photo.stack") { TimelineView() }
            Tab("Compare", systemImage: "square.split.2x1") { CompareView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
    }
}
