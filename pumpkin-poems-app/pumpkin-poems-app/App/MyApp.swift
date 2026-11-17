import SwiftData
import SwiftUI

@main struct MyApp: App {
    @State private var settings = AppSettings()
    @State private var router = Router()
    @State private var speech = SpeechPlayer()
    @State private var profiles = ProfileManager.shared
    @State private var content = ContentStore.shared
    @State private var account = AccountStore.shared
    @State private var sync = SyncEngine.shared
    @State private var network = NetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SpeechPlayer.warmUp()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG
                .modifier(DemoLaunchArguments())
                #endif
                // A different learner gets a fresh view tree on their own store.
                .id(profiles.identity)
                .modelContainer(profiles.container)
                .environment(settings)
                .environment(router)
                .environment(speech)
                .environment(profiles)
                .environment(content)
                .environment(account)
                .environment(sync)
                .environment(network)
                .preferredColorScheme(.light)
                .onChange(of: profiles.identity) { router.resetAll() }
                .task { await content.refreshManifest() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await content.refreshManifest()
                    await sync.syncNow()
                    await Telemetry.shared.flush()
                }
            case .background:
                Task { await Telemetry.shared.flush() }
            default:
                break
            }
        }
    }
}

#if DEBUG
/// Applies `-demoSeed YES`, `-demoTab …`, `-demoRoute …` and `-demoOrientation landscape|portrait` once at launch.
private struct DemoLaunchArguments: ViewModifier {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    /// Static: switching learner rebuilds the view tree, and the demo must still run only once per launch.
    private static var applied = false

    func body(content: Content) -> some View {
        content.task {
            guard !Self.applied else { return }
            Self.applied = true
            let store = ProgressStore(context: context)
            if UserDefaults.standard.bool(forKey: "demoSeed"), store.existingProgress(for: PoemLibrary.shared.poems[0].id) == nil {
                store.seedDemoData()
            }
            // Turns the simulator on its side (or back upright) for screenshots of the sideways layouts.
            let orientation: UIInterfaceOrientationMask? = switch UserDefaults.standard.string(forKey: "demoOrientation") {
            case "landscape": .landscapeRight
            case "portrait": .portrait
            default: nil
            }
            if let orientation {
                for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
                }
            }
            router.applyLaunchArguments()
            await applyNetworkDemos()
        }
    }

    /// `-demoDownloadPacks YES` downloads every published pack; `-demoSignIn <accountID>` (password
    /// `-demoPassword …`, default `demo-password`) registers the account if needed and signs in, creates the
    /// profile 小明 if needed, moves the guest records into it and syncs.
    private func applyNetworkDemos() async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "demoDownloadPacks") {
            let content = ContentStore.shared
            await content.refreshManifest()
            for pack in content.packs where !content.isInstalled(pack.id) {
                await content.download(pack)
            }
        }
        if let accountID = defaults.string(forKey: "demoSignIn"), !AccountStore.shared.isSignedIn {
            let account = AccountStore.shared
            let password = defaults.string(forKey: "demoPassword") ?? "demo-password"
            await account.signIn(accountID: accountID, password: password)
            if !account.isSignedIn, account.lastErrorCode == "invalid_credentials" {
                await account.register(accountID: accountID, password: password)
            }
            guard account.isSignedIn else { return }
            var profile = account.profiles.first
            if profile == nil {
                profile = await account.createProfile(nickname: "小明", stage: "p5")
            }
            if let profile {
                _ = await SyncEngine.shared.migrateGuest(into: profile.id)
            }
        }
    }
}
#endif
