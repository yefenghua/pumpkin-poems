import SwiftUI

// MARK: - AppTheme (docs/design/ui-delivery/ui-instruction.md §3–§4)

/// Single source of design variables. Screens read these instead of defining their own numbers.
enum AppTheme {
    enum Colors {
        /// Global warm page background.
        static let backgroundCream = Color(hex: 0xFFF9ED)
        /// Reading paper and cards.
        static let surfacePaper = Color(hex: 0xFFFCF5)
        /// Primary buttons.
        static let primaryGold = Color(hex: 0xFFBE28)
        /// Top of the primary button gradient.
        static let primaryGoldLight = Color(hex: 0xFFD85C)
        /// Selected navigation, emphasis.
        static let accentOrange = Color(hex: 0xF49A08)
        /// Card strokes.
        static let borderWarm = Color(hex: 0xF3D9AA)
        static let textPrimary = Color(hex: 0x28231C)
        static let textSecondary = Color(hex: 0x756A59)
        /// Current poem line.
        static let highlightCream = Color(hex: 0xFFE9A7)
        /// Read-aloud actions.
        static let audioBlue = Color(hex: 0x1683F5)
        static let audioBackground = Color(hex: 0xE3F1FF)
        static let successGreen = Color(hex: 0x438B45)
        /// Warm shadow colour; use with opacity ~0.08.
        static let shadow = Color(hex: 0x6B4A1E)
    }

    /// Tightened after review: cards sit closer to each other and to the screen edge
    /// so a main screen fits one phone height without feeling loose.
    enum Spacing {
        static let page: CGFloat = 16
        static let pageCompact: CGFloat = 14
        static let section: CGFloat = 14
        /// Gap between items inside one section (rows, chips, stacked cards).
        static let item: CGFloat = 10
        static let cardInset: CGFloat = 16
        static let shortcutGap: CGFloat = 10
        /// Bottom breathing room above the tab bar / safe area.
        static let pageBottom: CGFloat = 20
    }

    enum CornerRadius {
        static let container: CGFloat = 26
        static let paper: CGFloat = 28
        static let card: CGFloat = 20
        static let button: CGFloat = 18
    }

    enum Sizes {
        static let buttonHeight: CGFloat = 56
        static let pillHeight: CGFloat = 38
        static let hairline: CGFloat = 1
    }

    enum Typography {
        static let screenTitle = Font.system(size: 33, weight: .bold)
        static let heroLead = Font.system(size: 22, weight: .semibold)
        static let cardPoemTitle = Font.system(size: 31, weight: .bold)
        static let detailTitle = Font.system(size: 23, weight: .semibold)
        static let explanation = Font.system(size: 17.5, weight: .regular)
        static let primaryButton = Font.system(size: 19.5, weight: .semibold)
        static let label = Font.system(size: 15, weight: .medium)
    }
}

/// Semantic colour names used throughout the screens. Values follow `AppTheme.Colors`;
/// the older names are kept so every feature screen shares one palette.
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// 南瓜金: primary buttons, current node, reward highlight.
    static let pumpkinGold = AppTheme.Colors.primaryGold
    /// 南瓜橙: emphasis, selected navigation.
    static let pumpkinOrange = AppTheme.Colors.accentOrange
    /// 天空蓝: skies and listening decorations.
    static let skyBlue = Color(hex: 0x5B9BF3)
    /// 深湖蓝: links and blue buttons with white text.
    static let lakeBlue = Color(hex: 0x285DAD)
    /// 新叶绿: growth accents.
    static let leafGreen = Color(hex: 0x61B879)
    /// 深叶绿: success text and icons.
    static let deepLeaf = AppTheme.Colors.successGreen
    /// 桃粉: small warm accents.
    static let peachPink = Color(hex: 0xF58D96)
    /// 提示红: answers that need fixing; never a full-screen red.
    static let hintRed = Color(hex: 0xB84145)
    /// 奶油底: default page background.
    static let cream = AppTheme.Colors.backgroundCream
    /// 暖白: content cards and sheets.
    static let warmWhite = AppTheme.Colors.surfacePaper
    /// 可可棕: titles, poem lines, main text.
    static let cocoa = AppTheme.Colors.textPrimary
    /// 栗子棕: authors, captions, secondary text.
    static let chestnut = AppTheme.Colors.textSecondary
    /// 浅金边: card strokes and dividers, never the sole state indicator.
    static let paleGoldLine = AppTheme.Colors.borderWarm
    /// Pale gold fill for the selected poem line.
    static let paleGoldFill = AppTheme.Colors.highlightCream
    /// Light blue fill for audio and a selected quiz option.
    static let paleBlueFill = AppTheme.Colors.audioBackground
    static let paleGreenFill = Color(hex: 0xE5F4E9)
    static let paleRedFill = Color(hex: 0xFBEAEA)
}

enum Metrics {
    static let pagePadding = AppTheme.Spacing.page
    static let cardRadius = AppTheme.CornerRadius.card
    static let buttonRadius = AppTheme.CornerRadius.button
    static let buttonHeight = AppTheme.Sizes.buttonHeight
}

extension Font {
    static let pageTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let sectionTitle = Font.system(.title3, design: .rounded).weight(.semibold)
    static let cardTitle = Font.system(.title2, design: .rounded).weight(.semibold)
}

// MARK: - Containers

/// Warm paper card: cream-white fill, hairline warm-gold stroke, soft warm shadow.
struct CardBackground: ViewModifier {
    var fill: Color = .warmWhite
    var padding: CGFloat = AppTheme.Spacing.cardInset
    var radius: CGFloat = AppTheme.CornerRadius.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(AppTheme.Colors.borderWarm.opacity(0.9), lineWidth: AppTheme.Sizes.hairline))
            .shadow(color: AppTheme.Colors.shadow.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func card(fill: Color = .warmWhite, padding: CGFloat = AppTheme.Spacing.cardInset,
              radius: CGFloat = AppTheme.CornerRadius.card) -> some View {
        modifier(CardBackground(fill: fill, padding: padding, radius: radius))
    }

    /// Cream page background used by every screen.
    func pageBackground() -> some View {
        background(AppTheme.Colors.backgroundCream.ignoresSafeArea())
    }

    /// Light haptic for primary actions.
    func primaryActionHaptic<V: Equatable>(trigger: V) -> some View {
        sensoryFeedback(.impact(weight: .light), trigger: trigger)
    }
}

/// A sheet of warm paper with rounded top corners that continues downwards (学习页阅读纸面).
struct PaperSurface<Content: View>: View {
    var topRadius: CGFloat = AppTheme.CornerRadius.paper
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: topRadius, topTrailingRadius: topRadius, style: .continuous)
                    .fill(AppTheme.Colors.surfacePaper)
                    .shadow(color: AppTheme.Colors.shadow.opacity(0.12), radius: 14, y: -4)
            )
    }
}

// MARK: - Buttons

/// Gold primary action with dark text (never white on yellow). Soft sticker look:
/// light-to-gold vertical gradient, hairline stroke, shallow shadow.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var showsChevron = false
    /// Hugging, 44pt-high variant for inline actions such as 提交.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
            }
        }
        .font(compact ? .subheadline.weight(.semibold) : AppTheme.Typography.primaryButton)
        .foregroundStyle(AppTheme.Colors.textPrimary)
        .frame(minHeight: compact ? 44 : AppTheme.Sizes.buttonHeight)
        .frame(maxWidth: compact ? nil : .infinity)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(colors: [AppTheme.Colors.primaryGoldLight, AppTheme.Colors.primaryGold],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button, style: .continuous)
            .strokeBorder(Color(hex: 0xE9A512).opacity(0.55), lineWidth: 1))
        .shadow(color: AppTheme.Colors.shadow.opacity(0.14), radius: 6, y: 3)
        .opacity(isEnabled ? 1 : 0.5)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        .primaryActionHaptic(trigger: configuration.isPressed)
    }
}

/// Read-aloud action: pale blue ground, blue icon and text.
struct AudioButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : AppTheme.Typography.primaryButton)
            .foregroundStyle(AppTheme.Colors.audioBlue)
            .frame(minHeight: compact ? 44 : AppTheme.Sizes.buttonHeight)
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, 16)
            .background(AppTheme.Colors.audioBackground,
                        in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button, style: .continuous)
                .strokeBorder(AppTheme.Colors.audioBlue.opacity(0.18), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Deep blue action with white text, kept for existing screens.
struct BlueButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(.white)
            .frame(minHeight: compact ? 44 : Metrics.buttonHeight)
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, 16)
            .background(Color.lakeBlue, in: RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Quiet outlined action on warm white.
struct SoftButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(Color.cocoa)
            .frame(minHeight: compact ? 44 : Metrics.buttonHeight)
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, 16)
            .background(Color.warmWhite, in: RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous)
                .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Small components

/// Capsule tag for themes and states; selectable when used as a filter.
struct Chip: View {
    let title: String
    var systemImage: String?
    var isSelected = false
    var tint: Color = AppTheme.Colors.accentOrange
    /// Text colour on the selected fill; gold fills must use dark text.
    var selectedText: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isSelected ? selectedText : Color.cocoa)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(isSelected ? tint : Color.warmWhite, in: Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? Color.clear : AppTheme.Colors.borderWarm, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// Learning state label. Always text + icon, never color alone.
struct StatusBadge: View {
    let status: PoemStatus
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Label(status.title(settings), systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.12), in: Capsule())
    }
}

/// The three objective learning states (plus not started), from the product doc §3.3.
enum PoemStatus: Int, CaseIterable, Identifiable {
    case notStarted, read, passed, stable

    var id: Int { rawValue }

    init(_ progress: PoemProgress?) {
        guard let progress else { self = .notStarted; return }
        if progress.isStable { self = .stable }
        else if progress.hasPassed { self = .passed }
        else if progress.hasRead { self = .read }
        else { self = .notStarted }
    }

    func title(_ settings: AppSettings) -> String {
        switch self {
        case .notStarted: settings.t("未開始", "未开始")
        case .read: settings.t("已讀過", "已读过")
        case .passed: settings.t("練習通過", "练习通过")
        case .stable: settings.t("記憶較穩", "记忆较稳")
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted: "circle.dashed"
        case .read: "book"
        case .passed: "leaf"
        case .stable: "calendar.badge.checkmark"
        }
    }

    var color: Color {
        switch self {
        case .notStarted: .chestnut
        case .read: .lakeBlue
        case .passed: .deepLeaf
        case .stable: Color(hex: 0x9A5B12)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(Color.cocoa)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.chestnut)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}
