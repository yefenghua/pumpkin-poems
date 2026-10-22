import SwiftUI

/// Wraps children like text, so a poem line never shrinks to fit (visual guidelines §8):
/// at large Dynamic Type sizes it continues on the next row instead.
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

/// Poem text size: Dynamic Type scaled, times the in-app poem size setting.
struct PoemFont: ViewModifier {
    @Environment(AppSettings.self) private var settings
    @ScaledMetric(relativeTo: .title) private var base: CGFloat = 28

    func body(content: Content) -> some View {
        content.font(.system(size: base * settings.poemScale, weight: .medium, design: .serif))
    }
}

extension View {
    func poemFont() -> some View { modifier(PoemFont()) }
}

/// One poem line where annotated terms are tappable.
struct AnnotatedLineText: View {
    let line: PoemLine
    let annotations: [Annotation]
    var onTermTap: (Annotation) -> Void

    @Environment(AppSettings.self) private var settings

    private enum Segment: Identifiable {
        case plain(Int, Character)
        case term(Int, String, Annotation)

        var id: Int {
            switch self {
            case .plain(let index, _), .term(let index, _, _): index
            }
        }
    }

    var body: some View {
        FlowLayout {
            ForEach(segments) { segment in
                switch segment {
                case .plain(_, let character):
                    Text(String(character))
                case .term(_, let text, let annotation):
                    Button {
                        onTermTap(annotation)
                    } label: {
                        Text(text)
                            .underline(pattern: .dot, color: .pumpkinOrange)
                            .foregroundStyle(Color.cocoa)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(text)
                    .accessibilityHint(settings.t("查看字詞解釋", "查看字词解释"))
                }
            }
        }
        .poemFont()
        .foregroundStyle(Color.cocoa)
    }

    private var segments: [Segment] {
        // Reading-page lines are shown without their trailing punctuation, like a printed poem.
        let characters = Array(line.text(settings.script).withoutTrailingPunctuation)
        var spots: [(start: Int, end: Int, annotation: Annotation)] = []
        for annotation in annotations {
            for spot in annotation.occurrences(settings.script) where spot.lineID == line.id {
                spots.append((spot.start, spot.end, annotation))
            }
        }
        spots.sort { $0.start < $1.start }

        var result: [Segment] = []
        var index = 0
        while index < characters.count {
            if let spot = spots.first(where: { $0.start == index && $0.end <= characters.count && $0.end > index }) {
                result.append(.term(index, String(characters[spot.start..<spot.end]), spot.annotation))
                index = spot.end
            } else {
                result.append(.plain(index, characters[index]))
                index += 1
            }
        }
        return result
    }
}

/// Separate pill menus for text script and spoken language: they are independent settings,
/// so 繁體＋普通話 and 简体＋粤语 are both possible.
struct ScriptAndVoiceMenus: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        HStack(spacing: 8) {
            Menu {
                Picker(settings.t("文字", "文字"), selection: $settings.script) {
                    Text("繁體").tag(Script.hant)
                    Text("简体").tag(Script.hans)
                }
            } label: {
                pill(title: settings.script == .hant ? "繁體" : "简体")
            }
            .accessibilityLabel(settings.t("文字版本", "文字版本"))

            Menu {
                Picker(settings.t("朗讀", "朗读"), selection: $settings.voice) {
                    Text(settings.t("粵語", "粤语")).tag(VoiceLanguage.cantonese)
                    Text(settings.t("普通話", "普通话")).tag(VoiceLanguage.mandarin)
                }
            } label: {
                pill(title: voiceName)
            }
            .accessibilityLabel(settings.t("朗讀語言", "朗读语言"))
        }
    }

    private var voiceName: String {
        settings.voice == .cantonese ? settings.t("粵語", "粤语") : settings.t("普通話", "普通话")
    }

    private func pill(title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(1)
                .fixedSize()
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)
        .padding(.horizontal, 12)
        .frame(minHeight: AppTheme.Sizes.pillHeight)
        .frame(minWidth: 44, minHeight: 44)
        .background(AppTheme.Colors.surfacePaper.opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
        .shadow(color: AppTheme.Colors.shadow.opacity(0.1), radius: 4, y: 2)
    }
}

extension Poem {
    /// "李白 · 唐"
    func byline(_ settings: AppSettings) -> String {
        "\(settings.t(author.name)) · \(settings.t(dynasty))"
    }

    func difficultyTitle(_ settings: AppSettings) -> String {
        keyStage <= 1 ? settings.t("入門", "入门") : settings.t("進階", "进阶")
    }
}
