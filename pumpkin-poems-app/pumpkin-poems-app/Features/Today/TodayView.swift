import SwiftData
import SwiftUI

/// 今天: immersive scene → continue-learning card → 今日复习 / 飞花令 shortcuts (ui-instruction §5).
/// The top scene rotates daily through the three themes; the card vignette and the reading page
/// follow the current poem's explicit theme.
struct TodayView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var progressRecords: [PoemProgress]
    @Query private var mistakes: [Mistake]
    #if DEBUG
    /// Re-renders when the demo date shift changes.
    @AppStorage(AppClock.dayOffsetKey) private var dayOffset = 0
    #endif

    /// How far the continue card rides up over the scene's fade.
    private let cardOverlap: CGFloat = 56

    private var snapshot: LearningSnapshot { LearningSnapshot(progress: progressRecords) }

    var body: some View {
        #if DEBUG
        let _ = dayOffset
        #endif
        let snapshot = snapshot
        let now = AppClock.now
        let due = snapshot.dueReviews(mistakes: mistakes, now: now)
        let current = snapshot.inProgress
        let mainPoem = current?.poem ?? snapshot.nextUnstarted
        let heroTheme = PoemVisualTheme.daily(now)
        let cardTheme = PoemVisualTheme(poem: mainPoem)

        GeometryReader { geo in
            let width = geo.size.width
            let safeTop = geo.safeAreaInsets.top
            ScrollView {
                VStack(spacing: 0) {
                    heroScene(theme: heroTheme, width: width, safeTop: safeTop)
                    VStack(spacing: AppTheme.Spacing.section) {
                        ContinueLearningCard(current: current, poem: mainPoem, theme: cardTheme,
                                             isFirstEver: !snapshot.hasAnyRecord)
                        shortcuts(due: due)
                    }
                    .padding(.horizontal, pagePadding(width))
                    .padding(.top, -cardOverlap)
                    .padding(.bottom, AppTheme.Spacing.pageBottom)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func pagePadding(_ width: CGFloat) -> CGFloat {
        width < 380 ? AppTheme.Spacing.pageCompact : AppTheme.Spacing.page
    }

    // MARK: Scene

    /// Square scene shown whole (no stretching, 贝贝 never cropped); only the grass under the card is covered.
    private func heroScene(theme: PoemVisualTheme, width: CGFloat, safeTop: CGFloat) -> some View {
        // The square picture is anchored to its bottom so only sky is trimmed and 贝贝 stays whole;
        // the card then rides up over the fade at the bottom.
        let sceneHeight = min(width * 0.96, 500)
        let light = theme.prefersLightForeground
        return IllustratedSceneHeader(
            asset: theme.homeAsset,
            height: sceneHeight,
            fade: 0.24,
            imageAlignment: .bottom,
            textScrim: light ? Color(hex: 0x14204A).opacity(0.38) : AppTheme.Colors.backgroundCream.opacity(0.55)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(settings.t("今天", "今天"))
                    .font(AppTheme.Typography.screenTitle)
                Text(settings.t("和貝貝一起，\n讀懂一首詩", "和贝贝一起，\n读懂一首诗"))
                    .font(AppTheme.Typography.heroLead)
                    .lineSpacing(3)
            }
            .foregroundStyle(theme.foreground)
            .shadow(color: light ? Color.black.opacity(0.25) : Color.white.opacity(0.6), radius: 2, y: 1)
            .padding(.top, safeTop + 8)
            .padding(.horizontal, pagePadding(width))
            .frame(maxWidth: 560, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Shortcuts

    @ViewBuilder
    private func shortcuts(due: [Poem]) -> some View {
        let review = LearningShortcutCard(
            title: settings.t("今日複習", "今日复习"),
            subtitle: due.isEmpty ? settings.t("今天沒有要複習的詩", "今天没有要复习的诗")
                                  : settings.t("\(due.count) 首等你複習", "\(due.count) 首等你复习"),
            asset: ArtworkAsset.reviewScroll,
            artAlignment: .bottomLeading,
            artScale: 0.74
        ) { router.push(.review) }

        let game = LearningShortcutCard(
            title: settings.t("飛花令", "飞花令"),
            subtitle: settings.t("用學過的詩句接字", "用学过的诗句接字"),
            asset: ArtworkAsset.flowerGame,
            artAlignment: .bottomLeading,
            artScale: 0.72
        ) { router.push(.feiHuaLing(nil)) }

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppTheme.Spacing.shortcutGap) {
                review
                game
            }
        } else {
            HStack(alignment: .top, spacing: AppTheme.Spacing.shortcutGap) {
                review
                game
            }
        }
    }
}

// MARK: - Continue learning card

/// Paper card over the scene: small title, poem name, tagline and the gold action, with the theme's
/// vignette fading in from the right. Native text only; the artwork never sits behind text.
struct ContinueLearningCard: View {
    let current: (poem: Poem, step: LearningStep)?
    let poem: Poem?
    let theme: PoemVisualTheme?
    let isFirstEver: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router

    var body: some View {
        Group {
            if let poem {
                poemContent(poem)
            } else {
                allDone
            }
        }
        .padding(AppTheme.Spacing.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            if let theme {
                GeometryReader { proxy in
                    // The vignette fills exactly the area above the gold button, so its soft bottom edge
                    // is never cut flat by the button row; only the left side fades into the paper.
                    let buttonTop = proxy.size.height - AppTheme.Spacing.cardInset - AppTheme.Sizes.buttonHeight
                    let artHeight = max(96, buttonTop - 4)
                    ArtworkImage(name: theme.continueAsset, contentMode: .fit)
                        .frame(height: artHeight)
                        .mask(
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.32),
                            ], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .offset(x: 8, y: -2)
                }
                .allowsHitTesting(false)
            }
        }
        .background(AppTheme.Colors.surfacePaper,
                    in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.container, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.container, style: .continuous)
            .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.container - 5, style: .continuous)
            .strokeBorder(AppTheme.Colors.borderWarm.opacity(0.45), lineWidth: 1)
            .padding(5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.container, style: .continuous))
        .shadow(color: AppTheme.Colors.shadow.opacity(0.12), radius: 14, y: 6)
    }

    private func poemContent(_ poem: Poem) -> some View {
        let step = current?.step ?? .notStarted
        return VStack(alignment: .leading, spacing: 6) {
            Text(isFirstEver ? settings.t("開啟第一首詩", "开启第一首诗")
                 : current == nil ? settings.t("學下一首", "学下一首") : settings.t("繼續學習", "继续学习"))
                .font(AppTheme.Typography.label)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(settings.t(poem.title))
                .font(AppTheme.Typography.cardPoemTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.trailing, 110)
            Text(settings.t(poem.tagline))
                .font(.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 90)
            Button {
                open(poem, at: step)
            } label: {
                Text(actionTitle(step))
            }
            .buttonStyle(PrimaryButtonStyle(showsChevron: true))
            .padding(.top, 16)
            .accessibilityHint(stepTitle(step))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allDone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.t("全部練習通過", "全部练习通过"))
                .font(AppTheme.Typography.label)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(settings.t("\(PoemLibrary.shared.poems.count) 首詩都練習通過了！", "\(PoemLibrary.shared.poems.count) 首诗都练习通过了！"))
                .font(AppTheme.Typography.cardPoemTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .minimumScaleFactor(0.7)
            Text(settings.t("按時複習，讓記憶更穩。", "按时复习，让记忆更稳。"))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Button {
                router.selectedTab = .me
            } label: {
                Text(settings.t("看看成長冊", "看看成长册"))
            }
            .buttonStyle(PrimaryButtonStyle(showsChevron: true))
            .padding(.top, 8)
        }
    }

    private func open(_ poem: Poem, at step: LearningStep) {
        switch step {
        case .reciting: router.push(.recite(poem.id))
        case .quizzing: router.push(.quiz(poem.id))
        default: router.push(.poem(poem.id))
        }
    }

    private func actionTitle(_ step: LearningStep) -> String {
        switch step {
        case .notStarted: settings.t("開始學習", "开始学习")
        case .reading: settings.t("繼續學習", "继续学习")
        case .reciting: settings.t("繼續背誦", "继续背诵")
        case .quizzing, .completed: settings.t("去小測", "去小测")
        }
    }

    private func stepTitle(_ step: LearningStep) -> String {
        switch step {
        case .notStarted, .reading: settings.t("學到：理解詩意", "学到：理解诗意")
        case .reciting: settings.t("學到：分層背誦", "学到：分层背诵")
        case .quizzing, .completed: settings.t("學到：鞏固小測", "学到：巩固小测")
        }
    }
}

// MARK: - Shortcut card

/// 今日复习 / 飞花令: title top-left, artwork on the right, white round arrow bottom-right.
/// The whole card is the button; the artwork never intercepts touches.
struct LearningShortcutCard: View {
    let title: String
    let subtitle: String
    let asset: String
    var artAlignment: Alignment = .bottomTrailing
    var artScale: CGFloat = 1
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 40)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 134, alignment: .topLeading)
            .background(alignment: artAlignment) {
                GeometryReader { proxy in
                    ArtworkImage(name: asset, contentMode: .fit)
                        .frame(width: proxy.size.width * artScale)
                        // Fade the top of the artwork so the subtitle above it stays clean.
                        .mask(LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.38),
                        ], startPoint: .top, endPoint: .bottom))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: artAlignment)
                        .offset(x: -6, y: 10)
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                ArrowBadge().padding(12)
            }
            .background(AppTheme.Colors.surfacePaper,
                        in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous)
                .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous))
            .shadow(color: AppTheme.Colors.shadow.opacity(0.08), radius: 12, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card, style: .continuous))
        }
        .buttonStyle(ShortcutPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct ShortcutPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
