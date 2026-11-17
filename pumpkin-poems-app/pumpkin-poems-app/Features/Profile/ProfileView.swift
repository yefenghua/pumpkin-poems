import SwiftData
import SwiftUI

/// 我的／成长册 (ui-instruction §7): the garden scene with 贝贝, three collectible theme covers,
/// the three learning counts from real records, then personal bests, 错题回看 and settings.
struct ProfileView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var progressRecords: [PoemProgress]
    @Query private var attempts: [QuizAttempt]
    @Query private var mistakes: [Mistake]
    @Query private var games: [GameRecord]
    @Query(filter: #Predicate<PoemDraft> { !$0.pendingDeletion }) private var drafts: [PoemDraft]
    @Environment(SyncEngine.self) private var sync
    @Environment(ProfileManager.self) private var profiles
    @Environment(AccountStore.self) private var account

    private var library: PoemLibrary { PoemLibrary.shared }
    private let shelfOverlap: CGFloat = 30

    var body: some View {
        let snapshot = LearningSnapshot(progress: progressRecords)
        StorybookPage(overlap: shelfOverlap, sceneHeight: { width in
            // About 310pt on a phone; the picture keeps its top so the title sits on the light sky.
            min(width * 0.79, 420)
        }, scene: { metrics in
            scene(metrics)
        }, content: { metrics in
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                ThemeCollectionShelf(snapshot: snapshot)
                LearningStatsPanel(snapshot: snapshot)
                personalBests(snapshot)
                links
            }
            .storybookColumn(metrics)
        })
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Scene

    private func scene(_ metrics: StorybookMetrics) -> some View {
        IllustratedSceneHeader(asset: ArtworkAsset.growthScene, height: metrics.sceneHeight, fade: 0.2,
                               imageAlignment: .top, fadeEdge: metrics.fadeEdge) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(settings.t("我的成長冊", "我的成长册"))
                        .font(AppTheme.Typography.screenTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(account.profile(profiles.currentProfileID).map { settings.t("\($0.nickname) 的成長冊", "\($0.nickname) 的成长册") }
                         ?? settings.t("每一次複習，都有收穫", "每一次复习，都有收获"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    router.push(.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(AppTheme.Colors.surfacePaper.opacity(0.92), in: Circle())
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                .accessibilityLabel(settings.t("設定", "设置"))
            }
            .padding(metrics.sceneTextInsets)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Personal bests

    private func personalBests(_ snapshot: LearningSnapshot) -> some View {
        let calendar = Calendar.current
        let now = AppClock.now
        let thisWeek = progressRecords.filter { record in
            record.firstPassedAt.map { calendar.isDate($0, equalTo: now, toGranularity: .weekOfYear) } ?? false
        }.count
        let reviews = attempts.filter { $0.isReview && $0.passed }.count
        let entryBest = games.filter { $0.mode == FeiHuaLingMode.entry.rawValue }.map(\.score).max() ?? 0
        let challengeBest = games.filter { $0.mode == FeiHuaLingMode.challenge.rawValue }.map(\.score).max() ?? 0
        let fixed = mistakes.filter(\.isResolved).count
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: settings.t("個人最佳記錄", "个人最佳记录"))
            VStack(spacing: 0) {
                bestRow(icon: "calendar", title: settings.t("本週完成篇目", "本周完成篇目"), value: settings.t("\(thisWeek) 首", "\(thisWeek) 首"))
                Divider().overlay(AppTheme.Colors.borderWarm)
                bestRow(icon: "arrow.clockwise", title: settings.t("跨日複習通過", "跨日复习通过"), value: settings.t("\(reviews) 次", "\(reviews) 次"))
                Divider().overlay(AppTheme.Colors.borderWarm)
                bestRow(icon: "wand.and.stars", title: settings.t("修正錯題", "修正错题"), value: settings.t("\(fixed) 道", "\(fixed) 道"))
                Divider().overlay(AppTheme.Colors.borderWarm)
                bestRow(icon: "sparkles", title: settings.t("飛花令最高分（入門）", "飞花令最高分（入门）"), value: settings.t("\(entryBest) 分", "\(entryBest) 分"))
                Divider().overlay(AppTheme.Colors.borderWarm)
                bestRow(icon: "sparkles", title: settings.t("飛花令最高分（挑戰）", "飞花令最高分（挑战）"), value: settings.t("\(challengeBest) 分", "\(challengeBest) 分"))
            }
            .card(padding: 6)
        }
    }

    private func bestRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(Color.cocoa)
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.accentOrange)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private var links: some View {
        let open = mistakes.filter { MistakeState($0, library: library).isOpen }.count
        return VStack(spacing: AppTheme.Spacing.item) {
            Button {
                router.push(.myPoems)
            } label: {
                HStack {
                    Label(settings.t("我的詩集", "我的诗集"), systemImage: "pencil.and.scribble")
                    Spacer()
                    Text(drafts.isEmpty ? settings.t("寫第一首", "写第一首") : settings.t("\(drafts.count) 首", "\(drafts.count) 首"))
                        .foregroundStyle(Color.chestnut)
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(SoftButtonStyle())
            Button {
                router.push(.mistakes)
            } label: {
                HStack {
                    Label(settings.t("錯題回看", "错题回看"), systemImage: "tray.full")
                    Spacer()
                    Text(settings.t("\(open) 道", "\(open) 道"))
                        .foregroundStyle(Color.chestnut)
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(SoftButtonStyle())
            if let sceneMatch = library.sceneMatch {
                Button {
                    router.push(.sceneMatch(sceneMatch.theme))
                } label: {
                    HStack {
                        Label(settings.t("詩境配對", "诗境配对"), systemImage: "photo.on.rectangle.angled")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(SoftButtonStyle())
            }
            Button {
                router.push(.parentArea)
            } label: {
                HStack {
                    Label(settings.t("家長區域", "家长区域"), systemImage: "person.2")
                    Spacer()
                    if sync.pendingCount > 0 && !profiles.isGuest {
                        Text(settings.t("待同步", "待同步")).foregroundStyle(Color.chestnut)
                    }
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(SoftButtonStyle())
            Button {
                router.push(.settings)
            } label: {
                HStack {
                    Label(settings.t("設定", "设置"), systemImage: "gearshape")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(SoftButtonStyle())
        }
    }
}

// MARK: - Theme collection shelf

/// Three portrait covers, the outer ones tilted ±3°. A cover unlocks with the first passed practice in its
/// theme; the caption shows real collected / total counts. Tapping opens that theme's poems.
struct ThemeCollectionShelf: View {
    let snapshot: LearningSnapshot

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var library: PoemLibrary { PoemLibrary.shared }

    var body: some View {
        let themes = library.themes
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ArrowedShelf(items: themes) { theme in cover(theme, rotation: 0, width: 124) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) {
                        ForEach(Array(themes.enumerated()), id: \.element.id) { index, theme in
                            cover(theme, rotation: rotation(index, of: themes.count), width: 108)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    // More covers than fit: a scrolling shelf with ← / → on the edges that still hide some.
                    ArrowedShelf(items: themes) { theme in cover(theme, rotation: 0, width: 108) }
                }
            }
        }
    }

    private func rotation(_ index: Int, of count: Int) -> Double {
        guard count > 1 else { return 0 }
        if index == 0 { return -3 }
        if index == count - 1 { return 3 }
        return 0
    }

    private func cover(_ theme: PoemTheme, rotation: Double, width: CGFloat) -> some View {
        let poems = library.poems(inTheme: theme.id)
        let collected = snapshot.passedPoems(inTheme: theme.id)
        let unlocked = collected > 0
        let visual = PoemVisualTheme(themeID: theme.id)
        return Button {
            router.push(.themeAlbum(theme.id))
        } label: {
            Group {
                if let visual {
                    CollectionCover(theme: visual, title: settings.t(theme.name),
                                    caption: settings.t("\(collected) / \(poems.count) 首", "\(collected) / \(poems.count) 首"),
                                    isUnlocked: unlocked, width: width)
                } else {
                    ArtworkPlaceholder(name: theme.id)
                        .frame(width: width, height: width / 0.6)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .rotationEffect(.degrees(rotation))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.t(theme.name))
        .accessibilityValue(unlocked
                            ? settings.t("已收集 \(collected) / \(poems.count) 首", "已收集 \(collected) / \(poems.count) 首")
                            : settings.t("未解鎖，練習通過一首詩即可打開", "未解锁，练习通过一首诗即可打开"))
    }
}

// MARK: - Stats panel

/// One light panel, three columns separated by hairlines: 已读过 / 练习通过 / 记忆较稳, all from real records.
struct LearningStatsPanel: View {
    let snapshot: LearningSnapshot

    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    ForEach([PoemStatus.read, .passed, .stable]) { status in
                        column(status)
                        if status != .stable { Divider().overlay(AppTheme.Colors.borderWarm) }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach([PoemStatus.read, .passed, .stable]) { status in
                        column(status)
                        if status != .stable {
                            Rectangle().fill(AppTheme.Colors.borderWarm).frame(width: 1, height: 56)
                        }
                    }
                }
            }
            if !snapshot.hasAnyRecord {
                Text(settings.t("還沒有學習記錄。從「今天」開始第一首詩，這裏就會長出收穫。",
                                "还没有学习记录。从“今天”开始第一首诗，这里就会长出收获。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .card(padding: 14)
    }

    private func column(_ status: PoemStatus) -> some View {
        let count = snapshot.count(status)
        return VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: status.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xB07A1A))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: 0xFFF0C9), in: Circle())
                if count > 0 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(AppTheme.Colors.successGreen, in: Circle())
                        .overlay(Circle().strokeBorder(AppTheme.Colors.surfacePaper, lineWidth: 1.5))
                        .offset(x: 3, y: 3)
                }
            }
            Text(settings.t("\(count) 首", "\(count) 首"))
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text(status.title(settings))
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A collectible poem card. Earned on the first passed practice; level rises with cross-day reviews.
struct PoemPostcard: View {
    let poem: Poem
    let progress: PoemProgress?

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let earned = progress?.hasPassed ?? false
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Group {
                    if let theme = PoemVisualTheme(themeID: poem.theme) {
                        ArtworkImage(name: theme.coverAsset, contentMode: .fill)
                    } else {
                        ArtworkPlaceholder()
                    }
                }
                .frame(height: 96)
                .clipped()
                .saturation(earned ? 1 : 0.1)
                .opacity(earned ? 1 : 0.5)
                if !earned {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundStyle(Color.chestnut)
                        .padding(8)
                        .background(AppTheme.Colors.surfacePaper.opacity(0.9), in: Circle())
                }
            }
            .frame(height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.t(poem.title))
                    .font(.headline)
                    .foregroundStyle(Color.cocoa)
                    .lineLimit(1)
                if earned, let progress {
                    HStack(spacing: 3) {
                        ForEach(0..<ReviewScheduler.maxCardLevel, id: \.self) { level in
                            Image(systemName: level < progress.cardLevel ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(Color(hex: 0x9A5B12))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(settings.t("熟練度 \(progress.cardLevel) 級", "熟练度 \(progress.cardLevel) 级"))
                    StatusBadge(status: PoemStatus(progress))
                } else {
                    Text(settings.t("完成練習後獲得", "完成练习后获得"))
                        .font(.caption)
                        .foregroundStyle(Color.chestnut)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(earned ? Color.pumpkinGold : AppTheme.Colors.borderWarm,
                          style: StrokeStyle(lineWidth: earned ? 2 : 1.5, dash: earned ? [] : [6, 4])))
        .shadow(color: AppTheme.Colors.shadow.opacity(earned ? 0.1 : 0), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
    }
}
