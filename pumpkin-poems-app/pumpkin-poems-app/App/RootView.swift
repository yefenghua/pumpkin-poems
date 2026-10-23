import SwiftUI

/// Three-item main navigation, exactly 今天／詩庫／我的 (product doc §7.1).
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router

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
    }
}
