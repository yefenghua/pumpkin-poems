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
    @State private var showLearningPlan = false
    @State private var planDestination: Route?
    @State private var openLibraryAfterPlan = false
    #if DEBUG
    /// Re-renders when the demo date shift changes.
    @AppStorage(AppClock.dayOffsetKey) private var dayOffset = 0
    #endif

    /// How far the continue card rides up over the scene's fade.
    private let cardOverlap: CGFloat = 56

    private var snapshot: LearningSnapshot {
        LearningSnapshot(progress: progressRecords, targetKeyStage: settings.targetGrade?.keyStage)
    }

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
                                             isFirstEver: !snapshot.hasAnyRecord,
                                             planTotalCount: snapshot.planTotalCount)
                        planEntry(snapshot)
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
        .sheet(isPresented: $showLearningPlan, onDismiss: {
            if openLibraryAfterPlan {
                openLibraryAfterPlan = false
                planDestination = nil
                router.selectedTab = .library
            } else if let destination = planDestination {
                planDestination = nil
                router.push(destination)
            }
        }) {
            LearningPlanView(onOpen: { destination in
                openLibraryAfterPlan = false
                planDestination = destination
                showLearningPlan = false
            }, onOpenLibrary: {
                planDestination = nil
                openLibraryAfterPlan = true
                showLearningPlan = false
            })
        }
    }

    private func planEntry(_ snapshot: LearningSnapshot) -> some View {
        Button { showLearningPlan = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2).foregroundStyle(Color.pumpkinOrange)
                VStack(alignment: .leading, spacing: 4) {
                    Text((settings.targetGrade.map { settings.t($0.title) + " · " } ?? "")
                         + settings.t("學習計劃", "学习计划"))
                        .font(.headline).foregroundStyle(Color.cocoa)
                    Text(snapshot.planTotalCount == 0
                         ? settings.t("選一首詩，開始學習", "选一首诗，开始学习")
                         : settings.t("已完成 \(snapshot.planPassedCount)／\(snapshot.planTotalCount) 首", "已完成 \(snapshot.planPassedCount)／\(snapshot.planTotalCount) 首"))
                        .font(.subheadline).foregroundStyle(Color.chestnut)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(Color.chestnut)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.learning-plan")
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
                HStack(alignment: .center) {
                    Text(settings.t("今天", "今天"))
                        .font(AppTheme.Typography.screenTitle)
                    Spacer(minLength: 12)
                }
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
            title: settings.t("詩詞遊樂園", "诗词游乐园"),
            subtitle: settings.t("接詩、尋字、猜詩句", "接诗、寻字、猜诗句"),
            asset: ArtworkAsset.flowerGame,
            artAlignment: .bottomLeading,
            artScale: 0.72
        ) { router.push(.games) }

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
    let planTotalCount: Int

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

    @ViewBuilder
    private var allDone: some View {
        if planTotalCount == 0 {
            // TODO: Replace this library entry with the plan when secondary-school lessons are connected.
            VStack(alignment: .leading, spacing: 12) {
                Text(settings.t("選一首詩，開始學習", "选一首诗，开始学习"))
                    .font(AppTheme.Typography.cardPoemTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Button {
                    router.selectedTab = .library
                } label: {
                    Text(settings.t("打開詩庫", "打开诗库"))
                }
                .buttonStyle(PrimaryButtonStyle(showsChevron: true))
                .padding(.top, 8)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(settings.t("本學段練習完成", "本学段练习完成"))
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(settings.t("已完成 \(planTotalCount) 首詩", "已完成 \(planTotalCount) 首诗"))
                    .font(AppTheme.Typography.cardPoemTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .minimumScaleFactor(0.7)
                Button {
                    router.selectedTab = .me
                } label: {
                    Text(settings.t("成長冊", "成长册"))
                }
                .buttonStyle(PrimaryButtonStyle(showsChevron: true))
                .padding(.top, 8)
            }
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
