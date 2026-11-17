import SwiftData
import SwiftUI

/// 诗境配对 (L11): read the lines, pick the picture that fits them, then pick the words that prove it.
/// Picture and evidence get separate feedback, so a right picture with the wrong reason is said plainly.
/// The pictures never distort the poem (no real snow for 疑是地上霜); the wrong ones are the misreadings.
struct SceneMatchView: View {
    let themeID: String

    private enum Phase { case picture, evidence, roundDone }

    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context

    @State private var index = 0
    @State private var phase: Phase = .picture
    @State private var pickedPicture: String?
    @State private var pickedEvidence: Int?
    @State private var results: [(picture: Bool, evidence: Bool)] = []

    private var rounds: [SceneMatchContent.Round] {
        guard let content = PoemLibrary.shared.sceneMatch, content.theme == themeID else { return [] }
        return content.rounds.filter { PoemLibrary.shared.poem($0.poemID) != nil }
    }

    var body: some View {
        StorybookPage(overlap: 32, contentMaxWidth: 720, sceneHeight: { width in
            min(width * 0.5, 220)
        }, scene: { metrics in
            header(metrics)
        }, content: { metrics in
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                if rounds.indices.contains(index) {
                    roundView(rounds[index])
                } else if rounds.isEmpty {
                    Text(settings.t("這個主題還沒有詩境配對。", "这个主题还没有诗境配对。"))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .card()
                } else {
                    summary
                }
            }
            .storybookColumn(metrics, maxWidth: 720)
        })
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private func header(_ metrics: StorybookMetrics) -> some View {
        IllustratedSceneHeader(asset: ArtworkAsset.sceneMatchScene, height: metrics.sceneHeight, fade: 0.3,
                               imageAlignment: .top, textScrim: AppTheme.Colors.backgroundCream.opacity(0.5),
                               pendingDelivery: true, fadeEdge: metrics.fadeEdge) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    router.pop()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(AppTheme.Colors.surfacePaper.opacity(0.92), in: Circle())
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                .accessibilityLabel(settings.t("返回", "返回"))
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.t("詩境配對", "诗境配对"))
                        .font(AppTheme.Typography.screenTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(rounds.isEmpty ? "" : settings.t("第 \(min(index + 1, rounds.count)) / \(rounds.count) 組", "第 \(min(index + 1, rounds.count)) / \(rounds.count) 组"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            .padding(metrics.sceneTextInsets)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Round

    @ViewBuilder
    private func roundView(_ round: SceneMatchContent.Round) -> some View {
        let library = PoemLibrary.shared
        let poem = library.poem(round.poemID)
        VStack(spacing: 6) {
            ForEach(round.lineIDs, id: \.self) { lineID in
                if let line = poem?.line(lineID) {
                    Text(settings.t(line.text))
                        .poemFont()
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
            if let poem {
                Text("《\(settings.t(poem.title))》" + poem.byline(settings))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)

        VStack(alignment: .leading, spacing: 10) {
            Text(settings.t("哪一幅畫最像這兩句詩？", "哪一幅画最像这两句诗？"))
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
            HStack(spacing: 10) {
                ForEach(round.pictures, id: \.self) { pictureID in
                    pictureTile(round, pictureID)
                }
            }
            if let picked = pickedPicture {
                feedbackBox(correct: picked == round.answer,
                            title: picked == round.answer ? settings.t("畫面選對了", "画面选对了") : settings.t("這幅不太對", "这幅不太对"),
                            text: round.pictureFeedback[picked].map(settings.t) ?? "")
            }
        }
        .card()

        if phase != .picture {
            evidenceView(round)
        }

        if phase == .picture, let picked = pickedPicture, picked != round.answer {
            Button {
                pickedPicture = nil
            } label: {
                Label(settings.t("再選一次", "再选一次"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(SoftButtonStyle())
            Button {
                phase = .evidence
            } label: {
                Text(settings.t("看看依據", "看看依据"))
            }
            .buttonStyle(PrimaryButtonStyle(showsChevron: true))
        }
        if phase == .roundDone {
            Button {
                next()
            } label: {
                Text(index + 1 < rounds.count ? settings.t("下一組", "下一组") : settings.t("看結果", "看结果"))
            }
            .buttonStyle(PrimaryButtonStyle(showsChevron: true))
        }
    }

    private func pictureTile(_ round: SceneMatchContent.Round, _ pictureID: String) -> some View {
        let picture = PoemLibrary.shared.sceneMatch?.picture(pictureID)
        let picked = pickedPicture == pictureID
        let reveal = pickedPicture != nil
        let border: Color = !reveal ? AppTheme.Colors.borderWarm
            : pictureID == round.answer && (picked || phase != .picture) ? AppTheme.Colors.successGreen
            : picked ? Color.hintRed : AppTheme.Colors.borderWarm
        return Button {
            guard pickedPicture == nil || phase == .picture && pickedPicture != round.answer else { return }
            let firstTry = results.count == index
            pickedPicture = pictureID
            if firstTry { results.append((pictureID == round.answer, false)) }
            if pictureID == round.answer { phase = .evidence }
        } label: {
            VStack(spacing: 4) {
                ArtworkImage(name: pictureID, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                // Until the picture is delivered, the tile shows its description so the round still works.
                if !ArtworkAsset.isAvailable(pictureID), let picture {
                    Text(settings.t(picture.describe))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(5)
            .background(AppTheme.Colors.surfacePaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(border, lineWidth: reveal ? 2.5 : 1))
        }
        .buttonStyle(.plain)
        .disabled(phase != .picture)
        .accessibilityLabel(picture.map { settings.t($0.describe) } ?? pictureID)
    }

    private func evidenceView(_ round: SceneMatchContent.Round) -> some View {
        let evidence = round.evidence
        return VStack(alignment: .leading, spacing: 10) {
            Text(settings.t(evidence.prompt))
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(evidence.options.indices, id: \.self) { option in
                let state: OptionCard.State = pickedEvidence == nil ? .normal
                    : option == evidence.answer ? .correct : option == pickedEvidence ? .needsFix : .dimmed
                Button {
                    guard pickedEvidence == nil else { return }
                    pickedEvidence = option
                    let pictureRight = results.last?.picture ?? false
                    if results.count > index { results[index] = (pictureRight, option == evidence.answer) }
                    ProgressStore(context: context).recordSceneMatch(roundID: round.id, poemID: round.poemID,
                                                                     pictureCorrect: pictureRight,
                                                                     evidenceCorrect: option == evidence.answer)
                    phase = .roundDone
                } label: {
                    OptionCard(text: settings.t(evidence.options[option]), state: state)
                }
                .buttonStyle(.plain)
                .disabled(pickedEvidence != nil)
            }
            if let picked = pickedEvidence {
                let pictureRight = results.indices.contains(index) ? results[index].picture : false
                feedbackBox(correct: picked == evidence.answer,
                            title: evidenceTitle(pictureRight: pictureRight, evidenceRight: picked == evidence.answer),
                            text: settings.t(evidence.explanation))
            }
        }
        .card()
    }

    private func evidenceTitle(pictureRight: Bool, evidenceRight: Bool) -> String {
        switch (pictureRight, evidenceRight) {
        case (true, true): settings.t("畫面和依據都對了！", "画面和依据都对了！")
        case (true, false): settings.t("畫面選對了，但依據不是這幾個字。", "画面选对了，但依据不是这几个字。")
        case (false, true): settings.t("依據找對了，再對照一下畫面。", "依据找对了，再对照一下画面。")
        case (false, false): settings.t("再讀一讀詩句，找找關鍵的字。", "再读一读诗句，找找关键的字。")
        }
    }

    private func feedbackBox(correct: Bool, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: correct ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(correct ? Color.deepLeaf : Color.hintRed)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.cocoa)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(correct ? Color.paleGreenFill : Color.paleRedFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Summary

    private var summary: some View {
        let pictures = results.filter(\.picture).count
        let evidence = results.filter(\.evidence).count
        return VStack(spacing: 12) {
            MascotIllustration(size: 110)
            Text(settings.t("完成了 \(results.count) 組詩境配對", "完成了 \(results.count) 组诗境配对"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text(settings.t("第一次就選對畫面 \(pictures) 組，找對依據 \(evidence) 組。", "第一次就选对画面 \(pictures) 组，找对依据 \(evidence) 组。"))
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Button {
                index = 0
                results = []
                resetRound()
            } label: {
                Text(settings.t("再玩一次", "再玩一次"))
            }
            .buttonStyle(SoftButtonStyle())
            Button {
                router.pop()
            } label: {
                Text(settings.t("完成", "完成"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)
    }

    private func next() {
        index += 1
        resetRound()
    }

    private func resetRound() {
        phase = .picture
        pickedPicture = nil
        pickedEvidence = nil
    }
}
