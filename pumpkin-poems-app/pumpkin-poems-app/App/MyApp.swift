import SwiftData
import SwiftUI

@main struct MyApp: App {
    @State private var settings = AppSettings()
    @State private var router = Router()
    @State private var speech = SpeechPlayer()

    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG
                .modifier(DemoLaunchArguments())
                #endif
                .environment(settings)
                .environment(router)
                .environment(speech)
                .environment(\.locale, settings.locale)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: ProgressSchema.models)
    }
}

#if DEBUG
/// Applies `-demoSeed YES`, `-demoTab …` and `-demoRoute …` once at launch.
private struct DemoLaunchArguments: ViewModifier {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @State private var applied = false

    func body(content: Content) -> some View {
        content.task {
            guard !applied else { return }
            applied = true
            switch UserDefaults.standard.string(forKey: "demoLanguage") {
            case "cantonese": settings.applyPresentation(.cantonese)
            case "mandarin": settings.applyPresentation(.mandarin)
            default: break
            }
            let store = ProgressStore(context: context)
            if UserDefaults.standard.bool(forKey: "demoSeed"), store.existingProgress(for: PoemLibrary.shared.poems[0].id) == nil {
                store.seedDemoData()
            }
            router.applyLaunchArguments()
        }
    }
}
#endif
