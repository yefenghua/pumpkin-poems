import SwiftData
import SwiftUI

/// 分层背诵: full text → hide keywords → first character only → hide all.
/// Hidden characters keep their width so lines never jump; looking at a hint is never penalized.
struct RecitationView: View {
    let poemID: String

    enum Stage: Int, CaseIterable, Identifiable {
        case full, hideKeywords, firstCharacter, hidden
        var id: Int { rawValue }
    }

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(SpeechPlayer.self) private var speech
    @Environment(\.modelContext) private var context
    @Query private var progressRecords: [PoemProgress]

    @State private var stage: Stage = .hideKeywords
    @State private var selectedLineID: String?
    @State private var revealedLineIDs: Set<String> = []

    init(poemID: String) {
        self.poemID = poemID
        _progressRecords = Query(filter: #Predicate<PoemProgress> { $0.poemID == poemID })
    }

    private var poem: Poem? { PoemLibrary.shared.poem(poemID) }
    private var store: ProgressStore { ProgressStore(context: context) }

    var body: some View {
        if let poem {
            content(poem)
        } else {
            ContentUnavailableView(settings.t("找不到這首詩", "找不到这首诗"), systemImage: "book.closed")
        }
    }

    private func content(_ poem: Poem) -> some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.section) {
                Picker(settings.t("提示程度", "提示程度"), selection: $stage) {
                    ForEach(Stage.allCases) { stage in
                        Text(title(for: stage)).tag(stage)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)

                Text(stageHint)
                    .font(.subheadline)
                    .foregroundStyle(Color.chestnut)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 6) {
                    Text(settings.t(poem.title))
                        .font(.cardTitle)
                        .foregroundStyle(Color.cocoa)
                    Text(poem.byline(settings))
                        .font(.subheadline)
                        .foregroundStyle(Color.chestnut)
                        .padding(.bottom, 8)
                    ForEach(poem.lines) { line in
                        lineRow(line)
                    }
                }
                .card(padding: 16)

                lineTools(poem)
                selfAssessment
                Button {
                    speech.stop()
                    router.replaceTop(with: .quiz(poem.id))
                } label: {
                    Label(settings.t("去小測", "去小测"), systemImage: "checklist")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.bottom, AppTheme.Spacing.pageBottom)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle(settings.t("背誦", "背诵"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.advance(poem.id, to: .reciting)
            if selectedLineID == nil { selectedLineID = poem.lines.first?.id }
        }
        .onDisappear { speech.stop() }
        .onChange(of: stage) { revealedLineIDs.removeAll() }
    }

    private func lineRow(_ line: PoemLine) -> some View {
        let isSelected = selectedLineID == line.id
        let isRevealed = revealedLineIDs.contains(line.id)
        let characters = Array(line.text(settings.script))
        return FlowLayout {
            ForEach(characters.indices, id: \.self) { index in
                let hidden = !isRevealed && isHidden(index: index, character: characters[index], line: line)
                Text(String(characters[index]))
                    .opacity(hidden ? 0 : 1)
                    .background {
                        if hidden {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.paleGoldLine.opacity(0.7))
                                .padding(2)
                        }
                    }
            }
        }
        .poemFont()
        .foregroundStyle(Color.cocoa)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.paleGoldFill : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(isSelected ? Color.pumpkinGold : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { selectedLineID = line.id }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRevealed || stage == .full ? line.text(settings.script) : settings.t("隱藏的詩句", "隐藏的诗句"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selectedLineID = line.id }
    }

    private func isHidden(index: Int, character: Character, line: PoemLine) -> Bool {
        guard TextNormalizer.isHan(character) else { return false }
        switch stage {
        case .full: return false
        case .hideKeywords: return line.keyword.count == 2 && (line.keyword[0]..<line.keyword[1]).contains(index)
        case .firstCharacter: return index > 0
        case .hidden: return true
        }
    }

    private func lineTools(_ poem: Poem) -> some View {
        let line = poem.line(selectedLineID ?? "") ?? poem.lines[0]
        let isRevealed = revealedLineIDs.contains(line.id)
        return HStack(spacing: 12) {
            Button {
                speech.speak([(line.id, line.text(settings.script))], language: settings.voice)
            } label: {
                Label(settings.t("聽一句", "听一句"), systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(BlueButtonStyle())

            Button {
                if isRevealed { revealedLineIDs.remove(line.id) } else { revealedLineIDs.insert(line.id) }
            } label: {
                Label(isRevealed ? settings.t("收起提示", "收起提示") : settings.t("看提示", "看提示"),
                      systemImage: isRevealed ? "eye.slash" : "eye")
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(stage == .full)
        }
    }

    private var selfAssessment: some View {
        HStack(alignment: .center, spacing: 12) {
            MascotIllustration(size: 60)
            VStack(alignment: .leading, spacing: 8) {
                if progressRecords.first?.selfAssessedAt != nil {
                    Label(settings.t("已記下你的自評「我記住了」", "已记下你的自评“我记住了”"), systemImage: "hand.thumbsup")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.cocoa)
                } else {
                    Button {
                        store.recordSelfAssessment(poemID)
                    } label: {
                        Label(settings.t("我記住了", "我记住了"), systemImage: "hand.thumbsup")
                    }
                    .buttonStyle(SoftButtonStyle(compact: true))
                }
                Text(settings.t("這是自評，做完小測才會記錄練習成績。", "这是自评，做完小测才会记录练习成绩。"))
                    .font(.footnote)
                    .foregroundStyle(Color.chestnut)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var stageHint: String {
        switch stage {
        case .full: settings.t("先完整讀幾遍，可以點「聽一句」跟讀。", "先完整读几遍，可以点“听一句”跟读。")
        case .hideKeywords: settings.t("關鍵字藏起來了，試着唸出完整的詩句。", "关键字藏起来了，试着念出完整的诗句。")
        case .firstCharacter: settings.t("只看每句的第一個字，回想整句。", "只看每句的第一个字，回想整句。")
        case .hidden: settings.t("全部藏起來了！想不起來就看提示，沒關係。", "全部藏起来了！想不起来就看提示，没关系。")
        }
    }

    private func title(for stage: Stage) -> String {
        switch stage {
        case .full: settings.t("完整", "完整")
        case .hideKeywords: settings.t("隱關鍵字", "隐关键字")
        case .firstCharacter: settings.t("顯首字", "显首字")
        case .hidden: settings.t("全隱藏", "全隐藏")
        }
    }
}
