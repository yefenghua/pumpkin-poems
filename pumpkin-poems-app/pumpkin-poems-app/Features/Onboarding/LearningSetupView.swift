import SwiftUI

/// The first launch asks for both choices before creating the learner's plan.
struct LearningSetupView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var grade: LearningGrade?
    @State private var language: VoiceLanguage?

    private var script: Script { language?.preferredScript ?? settings.script }
    private var ready: Bool { grade != nil && language != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    MascotIllustration(size: 88)
                    Text(t("和貝貝一起學古詩", "和贝贝一起学古诗"))
                        .font(.title2.bold())
                        .foregroundStyle(Color.cocoa)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 14) {
                    Label(t("目標年級", "目标年级"), systemImage: "graduationcap")
                        .font(.headline).foregroundStyle(Color.cocoa)
                    gradeGroup(title: t("小學", "小学"), grades: LearningGrade.allCases.filter { $0.rawValue <= 6 })
                    gradeGroup(title: t("中學", "中学"), grades: LearningGrade.allCases.filter { $0.rawValue > 6 })
                }
                .card(padding: 14)

                VStack(alignment: .leading, spacing: 12) {
                    Label(t("學習語言", "学习语言"), systemImage: "speaker.wave.2")
                        .font(.headline).foregroundStyle(Color.cocoa)
                    languageChoice(.cantonese)
                    languageChoice(.mandarin)
                }
                .card(padding: 14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .safeAreaInset(edge: .bottom) {
            Button {
                guard let grade, let language else { return }
                settings.completeOnboarding(grade: grade, language: language)
            } label: {
                Text(t("開始學習", "开始学习"))
            }
            .buttonStyle(PrimaryButtonStyle(showsChevron: true))
            .disabled(!ready)
            .accessibilityIdentifier("learning-setup.start")
            .padding(16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Color.cream)
        }
    }

    private func gradeGroup(title: String, grades: [LearningGrade]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Color.chestnut)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                    count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
                ForEach(grades) { option in
                    let selected = grade == option
                    Button { grade = option } label: {
                        HStack(spacing: 5) {
                            Text(option.shortTitle(script)).font(.body.weight(.semibold))
                            Spacer(minLength: 0)
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline)
                        }
                        .foregroundStyle(Color.cocoa)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(selected ? Color.paleGoldFill : Color.cream, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                            selected ? Color.pumpkinOrange : Color.paleGoldLine, lineWidth: selected ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title(script))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("learning-setup.grade.\(option.rawValue)")
                }
            }
        }
    }

    private func languageChoice(_ option: VoiceLanguage) -> some View {
        let selected = language == option
        return Button { language = option } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title2).foregroundStyle(Color.pumpkinOrange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option == .cantonese ? t("粵語", "粤语") : t("普通話", "普通话"))
                        .font(.headline).foregroundStyle(Color.cocoa)
                    Text(option == .cantonese ? t("繁體中文", "繁体中文") : t("簡體中文", "简体中文"))
                        .font(.subheadline).foregroundStyle(Color.chestnut)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? Color.pumpkinOrange : Color.chestnut)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(selected ? Color.paleGoldFill : Color.cream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                selected ? Color.pumpkinOrange : Color.paleGoldLine, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("learning-setup.language.\(option.rawValue)")
    }

    private func t(_ hant: String, _ hans: String) -> String { script == .hant ? hant : hans }
}
