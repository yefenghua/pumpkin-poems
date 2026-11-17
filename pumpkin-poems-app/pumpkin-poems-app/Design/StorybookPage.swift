import SwiftUI

/// Sizes handed to a storybook screen's scene and content builders.
struct StorybookMetrics {
    /// Width the scene is drawn in: the page upright, the side panel (notch strip included) when the phone is on its side.
    var sceneWidth: CGFloat
    var sceneHeight: CGFloat
    /// Width of the column the content scrolls in.
    var contentWidth: CGFloat
    /// The phone is on its side: the scene stands as a panel on the left and the content scrolls beside it.
    var isSidePanel: Bool
    /// Keeps the scene's native text clear of the status bar, the notch, the page edge and (as a side
    /// panel) the home indicator, so a panel can also carry actions at its bottom.
    var sceneTextInsets: EdgeInsets

    /// Page margin for the content column: compact on narrow columns.
    var pagePadding: CGFloat { StorybookPage<EmptyView, EmptyView, EmptyView>.pagePadding(contentWidth) }
    /// Where the scene fades into the page: downwards upright, rightwards as a side panel.
    var fadeEdge: Edge { isSidePanel ? .trailing : .bottom }
}

/// The shell shared by the illustrated screens (今天, 学习页, 成长册, 飞花令, 小小诗人 …).
///
/// Upright: the scene sits on top, the content rides up over its fade and the whole page scrolls as one.
/// Phone turned sideways (compact height): the scene becomes a panel down the left edge, bleeding under the
/// notch, the status bar and the tab bar, and the content scrolls in its own column on the right, so no
/// screen is taller than the display. iPad keeps the upright flow (it never has a compact height).
struct StorybookPage<Scene: View, Content: View, Bar: View>: View {
    /// How far the content rides over the scene's fade (upright: upwards; sideways: leftwards).
    var overlap: CGFloat
    var contentMaxWidth: CGFloat = 760
    /// Scene height when upright, from the page width.
    var sceneHeight: (CGFloat) -> CGFloat
    @ViewBuilder var scene: (StorybookMetrics) -> Scene
    @ViewBuilder var content: (StorybookMetrics) -> Content
    /// Fixed bar under the scrolling content, e.g. the poem page's listen / recite bar.
    @ViewBuilder var bar: (StorybookMetrics) -> Bar
    /// A `safeAreaInset` holding an `EmptyView` insets the scroll view by its whole height on iOS 26, so
    /// pages without a bar must not install one at all.
    var hasBar = true

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Share of the screen (between the safe edges) the side panel takes.
    private let panelShare: CGFloat = 0.42
    private let sideOverlap: CGFloat = 26

    static func pagePadding(_ width: CGFloat) -> CGFloat {
        width < 380 ? AppTheme.Spacing.pageCompact : AppTheme.Spacing.page
    }

    var body: some View {
        GeometryReader { geo in
            if verticalSizeClass == .compact {
                sideBySide(geo)
            } else {
                stacked(geo)
            }
        }
    }

    // MARK: Upright

    private func stacked(_ geo: GeometryProxy) -> some View {
        let width = geo.size.width
        let pad = Self.pagePadding(width)
        let metrics = StorybookMetrics(
            sceneWidth: width, sceneHeight: sceneHeight(width), contentWidth: width, isSidePanel: false,
            sceneTextInsets: EdgeInsets(top: geo.safeAreaInsets.top + 8, leading: pad, bottom: 0, trailing: pad))
        return ScrollView {
            VStack(spacing: 0) {
                scene(metrics)
                content(metrics)
                    .padding(.top, -overlap)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollDismissesKeyboard(.interactively)
        .bottomBar(if: hasBar) { bar(metrics) }
    }

    // MARK: Sideways

    private func sideBySide(_ geo: GeometryProxy) -> some View {
        // The reader keeps the safe area (so the scroll column, its bar and the tab bar behave as usual);
        // only the scene panel is drawn larger than its slot and shifted so it also covers the notch strip
        // on the left and the bars above and below.
        let insets = geo.safeAreaInsets
        let visiblePanel = min(max(geo.size.width * panelShare, 240), 400)
        let panelWidth = visiblePanel + insets.leading
        let panelHeight = geo.size.height + insets.top + insets.bottom
        let contentWidth = geo.size.width - visiblePanel + sideOverlap
        let pad = Self.pagePadding(contentWidth)
        let metrics = StorybookMetrics(
            sceneWidth: panelWidth, sceneHeight: panelHeight, contentWidth: contentWidth, isSidePanel: true,
            sceneTextInsets: EdgeInsets(top: insets.top + 10, leading: insets.leading + pad,
                                        bottom: insets.bottom + 12, trailing: pad + 6))
        return HStack(spacing: 0) {
            scene(metrics)
                .frame(width: panelWidth, height: panelHeight)
                .clipped()
                .offset(x: -insets.leading / 2, y: (insets.bottom - insets.top) / 2)
                .frame(width: visiblePanel, height: geo.size.height)
            ScrollView {
                content(metrics)
                    .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .bottomBar(if: hasBar) { bar(metrics) }
            .padding(.leading, -sideOverlap)
        }
    }
}

extension StorybookPage where Bar == EmptyView {
    init(overlap: CGFloat, contentMaxWidth: CGFloat = 760,
         sceneHeight: @escaping (CGFloat) -> CGFloat,
         @ViewBuilder scene: @escaping (StorybookMetrics) -> Scene,
         @ViewBuilder content: @escaping (StorybookMetrics) -> Content) {
        self.overlap = overlap
        self.contentMaxWidth = contentMaxWidth
        self.sceneHeight = sceneHeight
        self.scene = scene
        self.content = content
        self.bar = { _ in EmptyView() }
        self.hasBar = false
    }
}

private extension View {
    @ViewBuilder func bottomBar<Bar: View>(if hasBar: Bool, @ViewBuilder bar: () -> Bar) -> some View {
        if hasBar {
            safeAreaInset(edge: .bottom, spacing: 0, content: bar)
        } else {
            self
        }
    }
}

extension View {
    /// Page margins, bottom breathing room and the width cap for a storybook content column.
    func storybookColumn(_ metrics: StorybookMetrics, maxWidth: CGFloat = 760) -> some View {
        padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, AppTheme.Spacing.pageBottom)
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
