import SwiftData
import SwiftUI

/// One theme of the growth book: its cover, the badge state and every poem card in that theme.
struct ThemeAlbumView: View {
    let themeID: String

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var progressRecords: [PoemProgress]

    private let library = PoemLibrary.shared

    var body: some View {
        let snapshot = LearningSnapshot(progress: progressRecords)
        if let theme = library.theme(themeID) {
            let poems = library.poems(inTheme: theme.id)
            let collected = snapshot.passedPoems(inTheme: theme.id)
            let earned = snapshot.isBadgeEarned(theme)
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    HStack(alignment: .top, spacing: 16) {
                        if let visual = PoemVisualTheme(themeID: theme.id) {
                            CollectionCover(theme: visual, title: settings.t(theme.name),
                                            caption: settings.t("\(collected) / \(poems.count) 首", "\(collected) / \(poems.count) 首"),
                                            isUnlocked: collected > 0, width: 104)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(settings.t(theme.summary))
                                .font(.body)
                                .foregroundStyle(Color.cocoa)
                                .fixedSize(horizontal: false, vertical: true)
                            Label(earned ? settings.t("徽章「\(settings.t(theme.badge))」已獲得", "徽章“\(settings.t(theme.badge))”已获得")
                                         : settings.t("練習通過全部 \(poems.count) 首，獲得「\(settings.t(theme.badge))」徽章",
                                                      "练习通过全部 \(poems.count) 首，获得“\(settings.t(theme.badge))”徽章"),
                                  systemImage: earned ? "rosette" : "lock")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(earned ? AppTheme.Colors.accentOrange : Color.chestnut)
                        }
                    }
                    .padding(.top, 8)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 190 : 150), spacing: 12)], spacing: 12) {
                        ForEach(poems) { poem in
                            Button {
                                router.push(.poem(poem.id))
                            } label: {
                                PoemPostcard(poem: poem, progress: snapshot.progress(poem.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, AppTheme.Spacing.pageBottom)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .pageBackground()
            .navigationTitle(settings.t(theme.name))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(settings.t("找不到這個主題", "找不到这个主题"), systemImage: "book.closed")
        }
    }
}
