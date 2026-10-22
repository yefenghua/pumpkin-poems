import SwiftData
import SwiftUI

/// 诗库: search titles and lines, filter by theme, difficulty, poet and learning state.
struct LibraryView: View {
    enum StatusFilter: Hashable {
        case all, favorites
        case status(PoemStatus)
    }

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var progressRecords: [PoemProgress]

    @State private var query = ""
    @State private var themeID: String?
    @State private var keyStage: Int?
    @State private var authorID: String?
    @State private var statusFilter: StatusFilter = .all

    private let library = PoemLibrary.shared

    var body: some View {
        let snapshot = LearningSnapshot(progress: progressRecords)
        let poems = filtered(snapshot)
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                themeCovers
                filters
                if poems.isEmpty {
                    ContentUnavailableView(settings.t("沒有找到符合的詩", "没有找到符合的诗"),
                                           systemImage: "magnifyingglass",
                                           description: Text(settings.t("換個關鍵字或篩選試試。", "换个关键字或筛选试试。")))
                        .padding(.top, 24)
                } else {
                    LazyVGrid(columns: columns, spacing: AppTheme.Spacing.item) {
                        ForEach(poems) { poem in
                            Button {
                                router.push(.poem(poem.id))
                            } label: {
                                PoemCard(poem: poem, progress: snapshot.progress(poem.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.bottom, AppTheme.Spacing.pageBottom)
        }
        .pageBackground()
        .navigationTitle(settings.t("詩庫", "诗库"))
        .searchable(text: $query, prompt: settings.t("搜尋詩名、詩句或詩人", "搜索诗名、诗句或诗人"))
    }

    private var columns: [GridItem] {
        sizeClass == .regular ? [GridItem(.adaptive(minimum: 300), spacing: 14)] : [GridItem(.flexible())]
    }

    private var themeCovers: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(library.themes) { theme in
                    let isSelected = themeID == theme.id
                    Button {
                        themeID = isSelected ? nil : theme.id
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Group {
                                if let visual = PoemVisualTheme(themeID: theme.id) {
                                    ArtworkImage(name: visual.coverAsset, contentMode: .fill)
                                } else {
                                    ArtworkPlaceholder()
                                }
                            }
                            .frame(width: 170, height: 84)
                            .clipped()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(settings.t(theme.name))
                                    .font(.headline)
                                    .foregroundStyle(Color.cocoa)
                                Text(settings.t(theme.summary))
                                    .font(.caption)
                                    .foregroundStyle(Color.chestnut)
                                    .lineLimit(2, reservesSpace: true)
                            }
                            .padding(10)
                        }
                        .frame(width: 170)
                        .background(Color.warmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isSelected ? AppTheme.Colors.accentOrange : AppTheme.Colors.borderWarm, lineWidth: isSelected ? 3 : 1))
                        .shadow(color: Color.cocoa.opacity(0.08), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker(settings.t("難度", "难度"), selection: $keyStage) {
                        Text(settings.t("全部難度", "全部难度")).tag(Int?.none)
                        Text(settings.t("入門", "入门")).tag(Int?.some(1))
                        Text(settings.t("進階", "进阶")).tag(Int?.some(2))
                    }
                } label: {
                    Chip(title: keyStage == nil ? settings.t("難度", "难度")
                         : keyStage == 1 ? settings.t("入門", "入门") : settings.t("進階", "进阶"),
                         systemImage: "chart.bar", isSelected: keyStage != nil)
                }
                Menu {
                    Picker(settings.t("詩人", "诗人"), selection: $authorID) {
                        Text(settings.t("全部詩人", "全部诗人")).tag(String?.none)
                        ForEach(library.authors, id: \.id) { author in
                            Text(settings.t(author.name)).tag(String?.some(author.id))
                        }
                    }
                } label: {
                    Chip(title: library.authors.first { $0.id == authorID }.map { settings.t($0.name) } ?? settings.t("詩人", "诗人"),
                         systemImage: "person", isSelected: authorID != nil)
                }
                Menu {
                    Picker(settings.t("學習狀態", "学习状态"), selection: $statusFilter) {
                        Text(settings.t("全部狀態", "全部状态")).tag(StatusFilter.all)
                        ForEach(PoemStatus.allCases) { status in
                            Text(status.title(settings)).tag(StatusFilter.status(status))
                        }
                        Text(settings.t("我的收藏", "我的收藏")).tag(StatusFilter.favorites)
                    }
                } label: {
                    Chip(title: statusTitle, systemImage: "checkmark.circle", isSelected: statusFilter != .all)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var statusTitle: String {
        switch statusFilter {
        case .all: settings.t("學習狀態", "学习状态")
        case .favorites: settings.t("我的收藏", "我的收藏")
        case .status(let status): status.title(settings)
        }
    }

    private func filtered(_ snapshot: LearningSnapshot) -> [Poem] {
        library.poems.filter { poem in
            if let themeID, poem.theme != themeID { return false }
            if let keyStage, poem.keyStage != keyStage { return false }
            if let authorID, poem.author.id != authorID { return false }
            switch statusFilter {
            case .all: break
            case .favorites: if snapshot.progress(poem.id)?.isFavorite != true { return false }
            case .status(let status): if snapshot.status(poem.id) != status { return false }
            }
            return library.matches(poem, query: query)
        }
    }

}

/// Poem row: title, poet and a clear learning state.
struct PoemCard: View {
    let poem: Poem
    let progress: PoemProgress?

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 14) {
            ThemeThumbnail(theme: PoemVisualTheme(themeID: poem.theme), size: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(settings.t(poem.title))
                        .font(.headline)
                        .foregroundStyle(Color.cocoa)
                    if progress?.isFavorite == true {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(Color.peachPink)
                            .accessibilityLabel(settings.t("已收藏", "已收藏"))
                    }
                }
                Text(poem.byline(settings) + " · " + poem.difficultyTitle(settings))
                    .font(.subheadline)
                    .foregroundStyle(Color.chestnut)
                Text(poem.lines.prefix(2).map { $0.text(settings.script) }.joined())
                    .font(.footnote)
                    .foregroundStyle(Color.chestnut)
                    .lineLimit(1)
                StatusBadge(status: PoemStatus(progress))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.chestnut.opacity(0.6))
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}
