import Observation
import SwiftUI

enum AppTab: Hashable {
    case today, library, me
}

enum Route: Hashable {
    case poem(String)
    case recite(String)
    case quiz(String)
    /// Retry specific questions from 错题回看.
    case retry([String])
    /// 飞花令, optionally with a preselected character (Simplified form).
    case feiHuaLing(String?)
    case mistakes
    case settings
    /// 今日复习 list.
    case review
    /// One theme of the growth book.
    case themeAlbum(String)
    /// 小小诗人: write a new piece (optionally preselecting a workshop theme) or edit a saved one.
    case poetWorkshop(PoetWorkshopDestination)
    /// 我的诗集.
    case myPoems
}

enum PoetWorkshopDestination: Hashable {
    case new(themeID: String?)
    case edit(UUID)
}

/// One navigation stack per tab, so flows like 阅读 → 背诵 → 小测 can replace and pop screens.
@Observable
final class Router {
    var selectedTab: AppTab = .today
    var todayPath: [Route] = []
    var libraryPath: [Route] = []
    var mePath: [Route] = []

    func push(_ route: Route) {
        mutateCurrentPath { $0.append(route) }
    }

    /// Replaces the top screen, e.g. recitation → quiz, so "back" returns to the poem.
    func replaceTop(with route: Route) {
        mutateCurrentPath { path in
            if !path.isEmpty { path.removeLast() }
            path.append(route)
        }
    }

    func pop() {
        mutateCurrentPath { path in
            if !path.isEmpty { path.removeLast() }
        }
    }

    func path(for tab: AppTab) -> Binding<[Route]> {
        Binding {
            switch tab {
            case .today: self.todayPath
            case .library: self.libraryPath
            case .me: self.mePath
            }
        } set: { newValue in
            switch tab {
            case .today: self.todayPath = newValue
            case .library: self.libraryPath = newValue
            case .me: self.mePath = newValue
            }
        }
    }

    #if DEBUG
    /// Debug launch arguments for demos and screenshots, e.g.
    /// `-demoTab library -demoRoute poem:hk-ks1-10` (routes: poem, recite, quiz, feihualing, mistakes, settings).
    func applyLaunchArguments(_ defaults: UserDefaults = .standard) {
        switch defaults.string(forKey: "demoTab") {
        case "library": selectedTab = .library
        case "me": selectedTab = .me
        default: break
        }
        guard let value = defaults.string(forKey: "demoRoute") else { return }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : nil
        let route: Route? = switch parts.first {
        case "poem": argument.map(Route.poem)
        case "recite": argument.map(Route.recite)
        case "quiz": argument.map(Route.quiz)
        case "feihualing": .feiHuaLing(argument)
        case "mistakes": .mistakes
        case "settings": .settings
        case "review": .review
        case "theme": argument.map(Route.themeAlbum)
        case "workshop": .poetWorkshop(.new(themeID: argument))
        case "mypoems": .myPoems
        default: nil
        }
        if let route { push(route) }
    }
    #endif

    private func mutateCurrentPath(_ change: (inout [Route]) -> Void) {
        switch selectedTab {
        case .today: change(&todayPath)
        case .library: change(&libraryPath)
        case .me: change(&mePath)
        }
    }
}

extension View {
    /// Destinations shared by every tab's navigation stack.
    func appDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .poem(let id): PoemDetailView(poemID: id)
            case .recite(let id): RecitationView(poemID: id)
            case .quiz(let id): QuizView(mode: .poem(id))
            case .retry(let ids): QuizView(mode: .retry(ids))
            case .feiHuaLing(let character): FeiHuaLingView(initialCharacter: character)
            case .mistakes: MistakesView()
            case .settings: SettingsView()
            case .review: ReviewListView()
            case .themeAlbum(let id): ThemeAlbumView(themeID: id)
            case .poetWorkshop(let destination): PoetWorkshopView(destination: destination)
            case .myPoems: MyPoemsView()
            }
        }
    }
}
