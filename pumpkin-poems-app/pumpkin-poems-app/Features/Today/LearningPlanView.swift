import SwiftData
import SwiftUI

/// The current grade's curriculum-stage plan, projected from existing learning records.
struct LearningPlanView: View {
    var onOpen: (Route) -> Void
    var onOpenLibrary: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Query private var progressRecords: [PoemProgress]
    @Query private var mistakes: [Mistake]

    var body: some View {
        let snapshot = LearningSnapshot(progress: progressRecords, targetKeyStage: settings.targetGrade?.keyStage)
        let due = snapshot.dueReviews(mistakes: mistakes, now: AppClock.now)
        let dueIDs = Set(due.map(\.id))
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    overview(snapshot)
                    if snapshot.planPoems.isEmpty {
                        libraryEntry
                    } else {
                        nextStep(snapshot, due: due)
                        SectionHeader(title: settings.t("學習清單", "学习清单"))
                        ForEach(snapshot.planPoems) { poem in
                            poemRow(poem, progress: snapshot.progress(poem.id), isDue: dueIDs.contains(poem.id))
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .pageBackground()
            .navigationTitle(settings.t("學習計劃", "学习计划"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("完成", "完成")) { dismiss() }
                }
            }
        }
    }

    private func overview(_ snapshot: LearningSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let grade = settings.targetGrade {
                Text(settings.t(grade.title)).font(.title2.bold()).foregroundStyle(Color.cocoa)
                Text(settings.t("所屬學段：", "所属学段：") + stageTitle(grade.keyStage))
                    .font(.subheadline).foregroundStyle(Color.chestnut)
            } else {
                Text(settings.t("全部篇目", "全部篇目")).font(.title2.bold()).foregroundStyle(Color.cocoa)
            }
            if snapshot.planTotalCount > 0 {
                Text(settings.t("已完成 \(snapshot.planPassedCount)／\(snapshot.planTotalCount) 首", "已完成 \(snapshot.planPassedCount)／\(snapshot.planTotalCount) 首"))
                    .font(.headline).foregroundStyle(Color.cocoa)
                ProgressView(value: Double(snapshot.planPassedCount), total: Double(snapshot.planTotalCount))
                    .tint(Color.deepLeaf)
                    .accessibilityLabel(settings.t("學習進度", "学习进度"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // TODO: Remove this entry when secondary-school lessons supply the corresponding stage plan.
    private var libraryEntry: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(settings.t("選一首詩，開始學習", "选一首诗，开始学习"), systemImage: "books.vertical")
                .font(.title3.bold()).foregroundStyle(Color.cocoa)
            Button(settings.t("打開詩庫", "打开诗库"), action: onOpenLibrary)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("learning-plan.open-library")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private func nextStep(_ snapshot: LearningSnapshot, due: [Poem]) -> some View {
        if let poem = due.first {
            nextCard(title: settings.t("今日複習", "今日复习"), poem: poem,
                     detail: settings.t("\(due.count) 首待複習", "\(due.count) 首待复习"),
                     action: settings.t("開始複習", "开始复习"), route: .quiz(poem.id))
        } else if let current = snapshot.inProgress {
            nextCard(title: settings.t("繼續學習", "继续学习"), poem: current.poem,
                     detail: stepTitle(current.step), action: stepAction(current.step),
                     route: route(for: current.poem, step: current.step))
        } else if let poem = snapshot.nextUnstarted {
            nextCard(title: settings.t("下一首", "下一首"), poem: poem,
                     detail: settings.t("讀詩意、練背誦、做小測", "读诗意、练背诵、做小测"),
                     action: settings.t("開始學習", "开始学习"), route: .poem(poem.id))
        } else if snapshot.isPlanComplete {
            Label(settings.t("本學段練習完成，按時複習吧。", "本学段练习完成，按时复习吧。"), systemImage: "checkmark.seal.fill")
                .foregroundStyle(Color.deepLeaf).font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    private func nextCard(title: String, poem: Poem, detail: String, action: String, route: Route) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Color.chestnut)
            Text(settings.t(poem.title)).font(.title3.bold()).foregroundStyle(Color.cocoa)
            Text(detail).font(.subheadline).foregroundStyle(Color.chestnut)
            Button(action) { onOpen(route) }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("learning-plan.next")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func poemRow(_ poem: Poem, progress: PoemProgress?, isDue: Bool) -> some View {
        Button {
            onOpen(isDue ? .quiz(poem.id) : route(for: poem, step: progress?.step ?? .notStarted))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: progress?.hasPassed == true ? "checkmark.circle.fill" : "book.closed")
                    .font(.title2).foregroundStyle(progress?.hasPassed == true ? Color.deepLeaf : Color.pumpkinOrange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.t(poem.title)).font(.headline).foregroundStyle(Color.cocoa)
                    Text(poem.byline(settings)).font(.caption).foregroundStyle(Color.chestnut)
                    if isDue {
                        Text(settings.t("今日複習", "今日复习")).font(.caption.weight(.semibold)).foregroundStyle(Color.hintRed)
                    } else if let date = progress?.nextReviewAt {
                        Text(settings.t("下次複習：", "下次复习：") + date.formatted(.dateTime.month().day().locale(settings.locale)))
                            .font(.caption).foregroundStyle(Color.chestnut)
                    } else {
                        Text(stepTitle(progress?.step ?? .notStarted)).font(.caption).foregroundStyle(Color.chestnut)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(Color.chestnut)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("learning-plan.poem.\(poem.id)")
    }

    private func route(for poem: Poem, step: LearningStep) -> Route {
        switch step {
        case .reciting: .recite(poem.id)
        case .quizzing: .quiz(poem.id)
        default: .poem(poem.id)
        }
    }

    private func stepTitle(_ step: LearningStep) -> String {
        switch step {
        case .notStarted: settings.t("未開始", "未开始")
        case .reading: settings.t("正在讀詩", "正在读诗")
        case .reciting: settings.t("正在背誦", "正在背诵")
        case .quizzing: settings.t("等待小測", "等待小测")
        case .completed: settings.t("已完成", "已完成")
        }
    }

    private func stepAction(_ step: LearningStep) -> String {
        switch step {
        case .reciting: settings.t("繼續背誦", "继续背诵")
        case .quizzing: settings.t("繼續小測", "继续小测")
        default: settings.t("繼續學習", "继续学习")
        }
    }

    private func stageTitle(_ stage: Int) -> String {
        switch stage {
        case 1: settings.t("小一至小三", "小一至小三")
        case 2: settings.t("小四至小六", "小四至小六")
        case 3: settings.t("中一至中三", "中一至中三")
        case 4: settings.t("中四至中六", "中四至中六")
        default: settings.t("全部篇目", "全部篇目")
        }
    }
}
