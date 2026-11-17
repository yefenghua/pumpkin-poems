import SwiftUI
import AVFoundation

/// Three-item main navigation, exactly 今天／詩庫／我的 (product doc §7.1).
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(SpeechPlayer.self) private var speech
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: router.path(for: .today)) {
                TodayView().appDestinations()
            }
            .tabItem { Label(settings.t("今天", "今天"), systemImage: "house") }
            .tag(AppTab.today)

            NavigationStack(path: router.path(for: .library)) {
                LibraryView().appDestinations()
            }
            .tabItem { Label(settings.t("詩庫", "诗库"), systemImage: "book") }
            .tag(AppTab.library)

            NavigationStack(path: router.path(for: .me)) {
                ProfileView().appDestinations()
            }
            .tabItem { Label(settings.t("我的", "我的"), systemImage: "person.crop.circle") }
            .tag(AppTab.me)
        }
        .tint(AppTheme.Colors.accentOrange)
        .fullScreenCover(isPresented: Binding(
            get: { !settings.hasCompletedOnboarding },
            set: { _ in }
        )) {
            LearningSetupView()
                .interactiveDismissDisabled()
        }
        .onChange(of: settings.voice) { _, _ in speech.stop() }
        .onChange(of: settings.script) { _, _ in speech.stop() }
        .onChange(of: router.selectedTab) { _, _ in speech.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { speech.refreshVoices() }
            else { speech.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            speech.refreshVoices()
        }
        .alert(settings.t("朗讀提示", "朗读提示"), isPresented: Binding(
            get: { speech.lastProblem != nil },
            set: { if !$0 { speech.lastProblem = nil } }
        )) {
            Button(settings.t("知道了", "知道了"), role: .cancel) { speech.lastProblem = nil }
        } message: {
            Text(speechProblemMessage)
        }
    }

    private var speechProblemMessage: String {
        switch speech.lastProblem {
        case .missingVoice:
            settings.t("所選語言的聲音尚未就緒。請先在系統設定的「輔助使用」中下載粵語或普通話聲音，再回到「我的 → 設定」重新檢查並試聽。", "所选语言的声音尚未就绪。请先在系统设置的“辅助功能”中下载粤语或普通话声音，再回到“我的 → 设置”重新检查并试听。")
        case .audioUnavailable, .didNotStart:
            settings.t("朗讀未能啟動，請檢查裝置音量和音訊輸出，再到設定重新試聽。", "朗读未能启动，请检查设备音量和音频输出，再到设置重新试听。")
        case nil: ""
        }
    }
}
