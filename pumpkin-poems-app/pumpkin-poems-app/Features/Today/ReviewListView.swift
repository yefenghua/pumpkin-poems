import SwiftData
import SwiftUI

/// 今日复习: the poems due today, open mistakes first (same rules as before, now on its own page).
struct ReviewListView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query private var progressRecords: [PoemProgress]
    @Query private var mistakes: [Mistake]

    var body: some View {
        let snapshot = LearningSnapshot(progress: progressRecords)
        let due = snapshot.dueReviews(mistakes: mistakes, now: AppClock.now)
        let openMistakes = Set(mistakes.filter { !$0.isResolved }.map(\.poemID))
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.item) {
                if due.isEmpty {
                    VStack(spacing: 12) {
                        MascotIllustration(size: 120)
                        Text(settings.t("今天沒有要複習的詩。", "今天没有要复习的诗。"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.cocoa)
                        Text(settings.t("學完一首詩後，貝貝會按時提醒你複習。", "学完一首诗后，贝贝会按时提醒你复习。"))
                            .font(.subheadline)
                            .foregroundStyle(Color.chestnut)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    SectionHeader(title: settings.t("今天建議複習 \(due.count) 首", "今天建议复习 \(due.count) 首"),
                                  subtitle: settings.t("有錯題的詩排在前面", "有错题的诗排在前面"))
                    ForEach(due) { poem in
                        Button {
                            router.push(.quiz(poem.id))
                        } label: {
                            HStack(spacing: 14) {
                                ThemeThumbnail(theme: PoemVisualTheme(themeID: poem.theme), size: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(settings.t(poem.title))
                                        .font(.headline)
                                        .foregroundStyle(Color.cocoa)
                                    Text(poem.byline(settings))
                                        .font(.subheadline)
                                        .foregroundStyle(Color.chestnut)
                                    if openMistakes.contains(poem.id) {
                                        Label(settings.t("有錯題待修正", "有错题待修正"), systemImage: "exclamationmark.circle")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.hintRed)
                                    }
                                }
                                Spacer(minLength: 0)
                                Text(settings.t("複習", "复习"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.Colors.accentOrange)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.Colors.accentOrange)
                            }
                            .card(padding: 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, AppTheme.Spacing.pageBottom)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle(settings.t("今日複習", "今日复习"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
