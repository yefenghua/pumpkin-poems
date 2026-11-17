import SwiftData
import SwiftUI

/// 学习周报 for parents: the last seven days of the current learner, from their own records.
struct WeeklyReportView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query(sort: \LearningEvent.at) private var events: [LearningEvent]
    @Query private var attempts: [QuizAttempt]
    @Query private var progressRecords: [PoemProgress]
    @Query private var mistakes: [Mistake]

    var body: some View {
        let report = makeReport()
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                Text(report.from.formatted(.dateTime.month().day()) + " – " + report.to.formatted(.dateTime.month().day()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                overview(report)
                if report.hasEnoughRecords {
                    dimension(settings.t("理解", "理解"), settings.t("詩意、字詞和詩句配對", "诗意、字词和诗句配对"), report.understanding)
                    dimension(settings.t("記憶", "记忆"), settings.t("填字、上下句和排序", "填字、上下句和排序"), report.memory)
                }
                review(report)
                if !report.commonMistakes.isEmpty {
                    mistakesCard(report)
                }
                suggestionCard(report)
                Text(settings.t("周報只根據練習結果，不把閱讀時長當成掌握程度。", "周报只根据练习结果，不把阅读时长当成掌握程度。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, AppTheme.Spacing.pageBottom)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle(settings.t("學習周報", "学习周报"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func makeReport() -> WeeklyReport {
        let calendar = Calendar.current
        let attemptByEvent = Dictionary(attempts.filter { !$0.eventID.isEmpty }.map { ($0.eventID, $0) }, uniquingKeysWith: { a, _ in a })
        var rounds: [WeeklyReport.Round] = []
        var days = Set<Date>()
        for event in events {
            if event.eventKind != .goal { days.insert(calendar.startOfDay(for: event.at)) }
            guard let kind = event.eventKind, kind == .quiz || kind == .retry, let poemID = event.poemID,
                  let payload = event.decode(LearningEventPayload.Quiz.self) else { continue }
            let attempt = attemptByEvent[event.id]
            rounds.append(.init(date: event.at, poemID: poemID, answers: payload.answers,
                                isReview: kind == .quiz ? (attempt?.isReview ?? false) : nil,
                                passed: attempt?.passed ?? QuizEvaluation(payload.answers).passed))
        }
        let due = LearningSnapshot(progress: progressRecords).dueReviews(mistakes: mistakes, now: AppClock.now).count
        return WeeklyReport(rounds: rounds, activeDays: days, dueNow: due, now: AppClock.now)
    }

    private func overview(_ report: WeeklyReport) -> some View {
        HStack(spacing: 0) {
            stat(settings.t("學習天數", "学习天数"), "\(report.studyDays)")
            Rectangle().fill(AppTheme.Colors.borderWarm).frame(width: 1, height: 44)
            stat(settings.t("練習次數", "练习次数"), "\(report.rounds)")
            Rectangle().fill(AppTheme.Colors.borderWarm).frame(width: 1, height: 44)
            stat(settings.t("到期待複習", "到期待复习"), "\(report.dueNow)")
        }
        .card(padding: 12)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(AppTheme.Colors.textPrimary)
            Text(title).font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func dimension(_ title: String, _ subtitle: String, _ ratio: WeeklyReport.Ratio) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).foregroundStyle(AppTheme.Colors.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                Text(ratio.isEnough ? settings.t("答對 \(ratio.correct)/\(ratio.total)", "答对 \(ratio.correct)/\(ratio.total)")
                                    : settings.t("記錄還不夠", "记录还不够"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ratio.isEnough ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
            }
            if ratio.isEnough {
                ProgressStrip(fraction: ratio.fraction)
            } else {
                Text(settings.t("本周答題少於 \(WeeklyReport.Ratio.minimumSample) 道，先不作判斷。", "本周答题少于 \(WeeklyReport.Ratio.minimumSample) 道，先不作判断。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .card()
    }

    private func review(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.t("跨日複習", "跨日复习")).font(.headline).foregroundStyle(AppTheme.Colors.textPrimary)
            Text(report.reviewsDone == 0
                 ? settings.t("本周還沒有到期的複習記錄。", "本周还没有到期的复习记录。")
                 : settings.t("完成 \(report.reviewsDone) 次，其中 \(report.reviewsUnaided) 次不用提示就通過。",
                              "完成 \(report.reviewsDone) 次，其中 \(report.reviewsUnaided) 次不用提示就通过。"))
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func mistakesCard(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.t("常錯的地方", "常错的地方")).font(.headline).foregroundStyle(AppTheme.Colors.textPrimary)
            ForEach(report.commonMistakes.prefix(3), id: \.category) { item in
                HStack {
                    Label(item.category.title(settings), systemImage: item.category.systemImage)
                    Spacer()
                    Text(settings.t("\(item.count) 次", "\(item.count) 次")).foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .font(.subheadline)
            }
        }
        .card()
    }

    private func suggestionCard(_ report: WeeklyReport) -> some View {
        HStack(alignment: .top, spacing: 10) {
            MascotIllustration(size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.t("陪學建議", "陪学建议")).font(.headline).foregroundStyle(AppTheme.Colors.textPrimary)
                Text(suggestionText(report.suggestion))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(fill: .paleGoldFill)
    }

    private func suggestionText(_ suggestion: WeeklyReport.Suggestion) -> String {
        let library = PoemLibrary.shared
        func title(_ id: String?) -> String { id.flatMap(library.poem).map { settings.t($0.title) } ?? "" }
        switch suggestion {
        case .explain(let id):
            return settings.t("請孩子用自己的話解釋《\(title(id))》，說說詩人看見了甚麼、想到了甚麼。",
                              "请孩子用自己的话解释《\(title(id))》，说说诗人看见了什么、想到了什么。")
        case .recite(let id):
            return settings.t("聽孩子背一次《\(title(id))》，卡住時只提示第一個字。", "听孩子背一次《\(title(id))》，卡住时只提示第一个字。")
        case .review(let count):
            return settings.t("有 \(count) 首詩到期複習，可以每天陪孩子做一兩首，不用一次做完。",
                              "有 \(count) 首诗到期复习，可以每天陪孩子做一两首，不用一次做完。")
        case .keepGoing(let id):
            return id == nil
                ? settings.t("保持節奏就好。可以請孩子說說最喜歡哪一句。", "保持节奏就好。可以请孩子说说最喜欢哪一句。")
                : settings.t("保持節奏就好。可以請孩子說說《\(title(id))》讓他想到甚麼畫面。", "保持节奏就好。可以请孩子说说《\(title(id))》让他想到什么画面。")
        case .startSmall:
            return settings.t("記錄還不夠。可以先陪孩子讀一首短詩，完成一次小測。", "记录还不够。可以先陪孩子读一首短诗，完成一次小测。")
        }
    }
}

/// 意见反馈: parents write freely; it is sent with the content and app versions, never with learning records.
struct FeedbackView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var category = "content"
    @State private var message = ""
    @State private var state: SendState = .editing
    @State private var feedbackID = UUID().uuidString.lowercased()

    private enum SendState: Equatable { case editing, sending, sent, failed }

    private struct Payload: Encodable {
        let id: String
        let installID: String
        let at: Date
        let category: String
        let message: String
        let contentVersion: String
        let appVersion: String
    }

    var body: some View {
        Form {
            Section(settings.t("類別", "类别")) {
                Picker(settings.t("類別", "类别"), selection: $category) {
                    Text(settings.t("內容／釋義", "内容／释义")).tag("content")
                    Text(settings.t("問題", "问题")).tag("bug")
                    Text(settings.t("建議", "建议")).tag("idea")
                    Text(settings.t("其他", "其他")).tag("other")
                }
                .pickerStyle(.segmented)
            }
            Section {
                TextEditor(text: $message)
                    .frame(minHeight: 160)
            } header: {
                Text(settings.t("想告訴我們的事", "想告诉我们的事"))
            } footer: {
                Text(settings.t("請不要填寫孩子的真實姓名、學校等個人資料。", "请不要填写孩子的真实姓名、学校等个人资料。"))
            }
            Section {
                Button(state == .sending ? settings.t("發送中…", "发送中…") : settings.t("發送", "发送")) {
                    Task { await send() }
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state == .sending)
                if state == .sent {
                    Label(settings.t("已收到，謝謝！", "已收到，谢谢！"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.Colors.successGreen)
                } else if state == .failed {
                    Text(settings.t("沒有發送成功，內容還在，稍後再試。", "没有发送成功，内容还在，稍后再试。"))
                        .foregroundStyle(Color.hintRed)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(settings.t("意見反饋", "意见反馈"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() async {
        state = .sending
        do {
            try await APIClient().send("POST", "/v1/feedback", body: Payload(
                id: feedbackID, installID: ServerConfig.installID, at: Date(), category: category,
                message: message, contentVersion: PoemLibrary.shared.version, appVersion: ServerConfig.appVersion))
            Telemetry.shared.log("feedback_sent", ["category": .string(category)])
            state = .sent
            message = ""
            feedbackID = UUID().uuidString.lowercased()
        } catch {
            state = .failed
        }
    }
}
