import SwiftUI
import UIKit

// MARK: - Theme → artwork mapping (ui-instruction.md "主题资源映射")

/// One visual theme per content theme. Chosen from the poem's explicit theme ID, never randomly and never from
/// the system colour scheme. 友情送别 and 生活与志趣 (phase 2) wait for artwork: until their PNGs are in the asset
/// catalog they show the grey pending area (see docs/design/pending-artwork-prompts.md).
enum PoemVisualTheme: String, CaseIterable, Identifiable {
    case moonlight, landscape, seasons, farewell, life

    var id: String { rawValue }

    /// Maps the content theme IDs (`moon` / `landscape` / `seasons`) to artwork.
    init?(themeID: String) {
        switch themeID {
        case "moon", "moonlight": self = .moonlight
        case "landscape": self = .landscape
        case "seasons": self = .seasons
        case "farewell": self = .farewell
        case "life": self = .life
        default: return nil
        }
    }

    init?(poem: Poem?) {
        guard let poem else { return nil }
        self.init(themeID: poem.theme)
    }

    /// The home scene rotates through the themes whose home picture is delivered, one per calendar day
    /// (honours the debug day offset), so 今天 never opens on a grey placeholder.
    static func daily(_ date: Date, calendar: Calendar = .current) -> PoemVisualTheme {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let delivered = allCases.filter { ArtworkAsset.isAvailable($0.homeAsset) }
        let pool = delivered.isEmpty ? [.moonlight, .landscape, .seasons] : delivered
        return pool[day % pool.count]
    }

    /// Square home scene with 贝贝 already painted in.
    var homeAsset: String {
        switch self {
        case .moonlight: "home_moonlight"
        case .landscape: "home_landscape"
        case .seasons: "home_seasons"
        case .farewell: "home_farewell"
        case .life: "home_life"
        }
    }

    /// Transparent vignette for the right side of the continue-learning card.
    var continueAsset: String {
        switch self {
        case .moonlight: "art_continue_moonlight"
        case .landscape: "art_continue_landscape"
        case .seasons: "art_continue_seasons"
        case .farewell: "art_continue_farewell"
        case .life: "art_continue_life"
        }
    }

    /// Reading page background, no character.
    var readingAsset: String {
        switch self {
        case .moonlight: "scene_poem_moonlight"
        case .landscape: "scene_poem_landscape"
        case .seasons: "scene_poem_seasons"
        case .farewell: "scene_poem_farewell"
        case .life: "scene_poem_life"
        }
    }

    /// Portrait album cover, no title baked in.
    var coverAsset: String {
        switch self {
        case .moonlight: "cover_moon"
        case .landscape: "cover_landscape"
        case .seasons: "cover_seasons"
        case .farewell: "cover_farewell"
        case .life: "cover_life"
        }
    }

    /// Text colour that reads on this theme's scenes: the moon night needs warm white, the others dark.
    var prefersLightForeground: Bool { self == .moonlight }

    var foreground: Color { prefersLightForeground ? Color(hex: 0xFFF6E3) : AppTheme.Colors.textPrimary }
    var secondaryForeground: Color { prefersLightForeground ? Color(hex: 0xFFF6E3).opacity(0.86) : AppTheme.Colors.textSecondary }
}

enum ArtworkAsset {
    static let mascotPeeking = "mascot_peeking"
    static let growthScene = "scene_growth_with_mascot"
    static let reviewScroll = "art_review_scroll"
    static let flowerGame = "art_flower_game"

    /// 飞花令 page header: 贝贝 in a spring garden catching falling petals. Wide, opaque.
    static let gameScene = "scene_feihualing"
    /// 小小诗人 page header: 贝贝 at a low desk with brush, ink and paper. Wide, opaque.
    static let workshopScene = "scene_poet_workshop"
    /// 学习完成页 header: 贝贝 jumping with the newly earned poem card. Wide, opaque.
    static let celebrationScene = "scene_celebration"
    /// 我的诗集: a small hand-bound notebook with brush and petals. Transparent PNG.
    static let poemBookArt = "art_poem_book"

    // Phase 2, not delivered yet (docs/design/pending-artwork-prompts.md). Until a PNG is dropped into
    // `PoetryArtwork.xcassets` under exactly this name, the screen shows the neutral grey area instead.
    /// 家长区域 header: a quiet reading corner with 贝贝 and a parent's chair. Wide, opaque.
    static let parentScene = "scene_parent_corner"
    /// 诗境配对 header: 贝贝 holding up picture cards under a moonlit sky. Wide, opaque.
    static let sceneMatchScene = "scene_scene_match"

    /// Names that are on the pending list: missing ones render grey, not as a "缺少素材" error.
    static var pending: Set<String> {
        var names: Set<String> = [parentScene, sceneMatchScene]
        for theme in [PoemVisualTheme.farewell, .life] {
            names.formUnion([theme.homeAsset, theme.continueAsset, theme.readingAsset, theme.coverAsset])
        }
        names.formUnion(PoemLibrary.shared.sceneMatch?.pictures.map(\.id) ?? [])
        return names
    }

    /// Answers already given by `isAvailable`. UIKit caches a hit but not a miss: every lookup of an
    /// undelivered asset searches the catalogs and the bundle again, which view bodies cannot afford.
    @MainActor private static var availability: [String: Bool] = [:]

    /// True when the image exists in an asset catalog of the app bundle.
    @MainActor static func isAvailable(_ name: String) -> Bool {
        if let known = availability[name] { return known }
        let found = UIImage(named: name) != nil
        availability[name] = found
        return found
    }
}

// MARK: - Safe image loading

/// Decorative artwork that never crashes or shows a broken image: when the asset is missing it renders
/// a clearly marked neutral placeholder so missing deliveries are visible, not silent.
struct ArtworkImage: View {
    let name: String
    var contentMode: ContentMode = .fill

    var body: some View {
        if ArtworkAsset.isAvailable(name) {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .accessibilityHidden(true)
        } else if ArtworkAsset.pending.contains(name) {
            PendingArtwork(name: name, compact: true)
        } else {
            ArtworkPlaceholder(name: name)
        }
    }
}

/// Neutral paper area used when an asset is absent or a poem has no mapped theme.
struct ArtworkPlaceholder: View {
    var name: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFFF3DA), AppTheme.Colors.backgroundCream],
                           startPoint: .top, endPoint: .bottom)
            if let name {
                Text("缺少素材：\(name)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(6)
                    .background(AppTheme.Colors.surfacePaper.opacity(0.8), in: Capsule())
            }
        }
        .accessibilityHidden(true)
    }
}

/// Grey stand-in for artwork that has not been generated yet. Deliberately plain so nobody mistakes
/// it for final visuals; swaps to the real picture automatically once the asset exists.
struct PendingArtwork: View {
    let name: String
    /// Small areas show only the icon; the asset name would wrap.
    var compact = false

    var body: some View {
        if ArtworkAsset.isAvailable(name) {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .accessibilityHidden(true)
        } else {
            // Label sits top-right below the status bar: titles live top-left and the cream fade covers the bottom.
            ZStack(alignment: compact ? .center : .topTrailing) {
                Color(hex: 0xD9D5CE)
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(compact ? .title3 : .caption)
                    if !compact {
                        Text(name)
                            .font(.caption2.monospaced())
                    }
                }
                .foregroundStyle(Color(hex: 0x7A746B))
                .padding(.trailing, compact ? 0 : 12)
                .padding(.top, compact ? 0 : 64)
            }
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Shared illustrated components

/// The small pumpkin helper that peeks over the explanation box. Only `mascot_peeking` is delivered,
/// so every helper moment uses it; it never intercepts touches.
struct MascotIllustration: View {
    var size: CGFloat = 72
    /// Flip left-to-right, e.g. when the helper leans on a box from the right.
    var mirrored = false

    var body: some View {
        ArtworkImage(name: ArtworkAsset.mascotPeeking, contentMode: .fit)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A full-bleed scene that extends into the top safe area and fades into the cream page at its bottom edge.
struct IllustratedSceneHeader<Overlay: View>: View {
    let asset: String?
    var height: CGFloat
    /// Fraction of the scene height covered by the bottom fade into the cream page.
    var fade: CGFloat = 0.22
    /// Which part of the picture survives when the frame is shorter than the picture (.bottom keeps 贝贝's feet).
    var imageAlignment: Alignment = .center
    /// Extra darkening/lightening behind top-left text, when the scene needs it.
    var textScrim: Color? = nil
    /// The asset is on the pending list: show the grey stand-in rather than the "缺少素材" paper when absent.
    var pendingDelivery = false
    /// Which edge melts into the page: the bottom when the scene sits on top, the trailing edge when it
    /// stands as a side panel with the content beside it (`fade` is then a fraction of the width).
    var fadeEdge: Edge = .bottom
    /// Colour of the page the scene fades into.
    var fadeColor: Color = AppTheme.Colors.backgroundCream
    @ViewBuilder var overlay: Overlay

    var body: some View {
        let height = height
        let sideways = fadeEdge == .trailing
        ZStack(alignment: .topLeading) {
            // The frame is sized by the container, never by the bitmap: the image fills it and is clipped.
            // Pulling the page down past the top scales the picture up about its bottom edge by the same
            // distance, so it zooms and stays pinned to the top; the scroll view's rubber band limits how far.
            // The stretch is a visual effect applied after layout, so scrolling never re-runs this body.
            // A side panel is not in a scroll view and never stretches.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay(alignment: imageAlignment) {
                    if let asset, pendingDelivery {
                        PendingArtwork(name: asset)
                    } else if let asset {
                        ArtworkImage(name: asset, contentMode: .fill)
                    } else {
                        ArtworkPlaceholder()
                    }
                }
                .clipped()
                .overlay(alignment: .top) {
                    if let textScrim {
                        LinearGradient(colors: [textScrim, textScrim.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: height * 0.45)
                    }
                }
                .visualEffect { content, proxy in
                    let pull = sideways ? 0 : max(0, proxy.frame(in: .scrollView).minY)
                    return content.scaleEffect(1 + pull / height, anchor: .bottom)
                }
                .overlay(alignment: sideways ? .trailing : .bottom) {
                    let stops: [Gradient.Stop] = [
                        .init(color: fadeColor.opacity(0), location: 0),
                        .init(color: fadeColor.opacity(0.55), location: 0.55),
                        .init(color: fadeColor, location: 1),
                    ]
                    if sideways {
                        GeometryReader { proxy in
                            LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
                                .frame(width: proxy.size.width * fade)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    } else {
                        LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
                            .frame(height: height * fade)
                    }
                }
            overlay
        }
        .frame(height: height)
    }
}

/// Portrait collectible cover with a thick cream border and a native label underneath the picture.
struct CollectionCover: View {
    let theme: PoemVisualTheme
    let title: String
    var caption: String?
    var isUnlocked: Bool
    var width: CGFloat = 108

    /// Picture height for the 0.6 cover ratio; the label below grows with Dynamic Type.
    private var pictureHeight: CGFloat { width / 0.6 - 44 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ArtworkImage(name: theme.coverAsset, contentMode: .fill)
                    .frame(width: width - 10, height: pictureHeight)
                    .saturation(isUnlocked ? 1 : 0.1)
                    .opacity(isUnlocked ? 1 : 0.55)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .padding(10)
                        .background(AppTheme.Colors.surfacePaper.opacity(0.92), in: Circle())
                }
            }
            .padding(.top, 5)
            VStack(spacing: 1) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .frame(minHeight: 39)
        }
        .frame(width: width)
        .background(AppTheme.Colors.surfacePaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
        .shadow(color: AppTheme.Colors.shadow.opacity(0.12), radius: 10, y: 5)
    }
}

/// Small theme thumbnail for lists (诗库 rows), derived from the album cover so it matches the collection.
struct ThemeThumbnail: View {
    let theme: PoemVisualTheme?
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let theme {
                ArtworkImage(name: theme.coverAsset, contentMode: .fill)
            } else {
                ArtworkPlaceholder()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1))
    }
}

/// Circular white arrow used in the bottom-right of tappable shortcut cards.
struct ArrowBadge: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .frame(width: 34, height: 34)
            .background(Color.white, in: Circle())
            .shadow(color: AppTheme.Colors.shadow.opacity(0.14), radius: 6, y: 2)
            .accessibilityHidden(true)
    }
}

#Preview("Covers") {
    HStack(spacing: 14) {
        CollectionCover(theme: .moonlight, title: "月与思乡", caption: "2 / 4", isUnlocked: true).rotationEffect(.degrees(-3))
        CollectionCover(theme: .landscape, title: "山水田园", caption: "0 / 4", isUnlocked: false)
        CollectionCover(theme: .seasons, title: "四季景物", caption: "4 / 4", isUnlocked: true).rotationEffect(.degrees(3))
    }
    .padding()
    .pageBackground()
}
