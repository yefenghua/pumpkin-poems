import SwiftData
import SwiftUI

/// 今日复习: today's share of the due poems (open mistakes first), then the backlog for the next days.
/// Nothing is forced: a backlog can be cleared over several days.
struct ReviewListView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query private var progressRecords: [PoemProgress]
    @Query private var mistakes: [Mistake]
    @Query private var attempts: [QuizAttempt]
    @Environment(\.modelContext) private var context

    var body: some View {
        let snapshot = LearningSnapshot(progress: progressRecords)
        let due = snapshot.dueReviews(mistakes: mistakes, now: AppClock.now)
        let plan = snapshot.dailyPlan(goal: ProgressStore(context: context).currentGoal(), mistakes: mistakes,
                                      attempts: attempts, now: AppClock.now)
        let todayIDs = Set(plan.reviewsToday)
        let openMistakes = Set(mistakes.filter { !$0.isResolved }.map(\.poemID))
        let hinted = Set(progressRecords.filter(\.lastUsedHints).map(\.poemID))
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
                    let today = due.filter { todayIDs.contains($0.id) }
                    let later = due.filter { !todayIDs.contains($0.id) }
                    if !today.isEmpty {
                        SectionHeader(title: settings.t("今天建議複習 \(today.count) 首", "今天建议复习 \(today.count) 首"),
                                      subtitle: settings.t("有錯題的詩排在前面", "有错题的诗排在前面"))
                        rows(today, openMistakes: openMistakes, hinted: hinted)
                    } else if plan.isPaused {
                        SectionHeader(title: settings.t("今天休息", "今天休息"),
                                      subtitle: settings.t("想做的話，下面的也可以複習。", "想做的话，下面的也可以复习。"))
                    }
                    if !later.isEmpty {
                        SectionHeader(title: settings.t("明天再做也可以（\(later.count) 首）", "明天再做也可以（\(later.count) 首）"),
                                      subtitle: settings.t("積下來的複習分幾天完成，不用一次做完。", "积下来的复习分几天完成，不用一次做完。"))
                            .padding(.top, 6)
                        rows(later, openMistakes: openMistakes, hinted: hinted)
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

    private func rows(_ poems: [Poem], openMistakes: Set<String>, hinted: Set<String>) -> some View {
        ForEach(poems) { poem in
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
                            Label(settings.t("有錯題待鞏固", "有错题待巩固"), systemImage: "exclamationmark.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.hintRed)
                        } else if hinted.contains(poem.id) {
                            Label(settings.t("上次用了提示", "上次用了提示"), systemImage: "lightbulb")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
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
