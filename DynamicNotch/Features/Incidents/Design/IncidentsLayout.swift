import Foundation

/// Medidas de la isla de incidencias. Content [A] las usa en `size`/`dynamicIslandSize`; las
/// vistas [B] las usan para maquetar, de modo que alto calculado y alto dibujado coincidan.
enum IncidentsLayout {
    static let maxVisibleRows = 5

    // MARK: Píldora compacta

    static let compactSymbolSize: CGFloat = 16
    static let compactCountSize: CGFloat = 14
    static let compactLabelSize: CGFloat = 10
    static let compactDotSize: CGFloat = 5
    static let compactLeadingPadding: (notch: CGFloat, notchless: CGFloat) = (14, 10)
    static let compactTrailingPadding: (notch: CGFloat, notchless: CGFloat) = (12, 12)

    static func compactExtraWidth(isNotchless: Bool) -> CGFloat {
        isNotchless ? 80 : 100
    }

    // MARK: Tarjeta de aviso

    static let alertExtraHeight: CGFloat = 90
    static let alertExtraWidth: (notch: CGFloat, notchless: CGFloat) = (310, 372)
    static let alertOrbSize: CGFloat = 46
    static let alertButtonSize: CGFloat = 26
    static let alertCornerRadius: (top: CGFloat, bottom: CGFloat) = (24, 34)
    static let alertPadding: (leading: CGFloat, trailing: CGFloat, bottom: CGFloat) = (42, 36, 15)
    static let alertNotchlessPadding: (leading: CGFloat, trailing: CGFloat, bottom: CGFloat) = (19, 17, 17)

    static func alertSize(baseWidth: CGFloat, baseHeight: CGFloat, isNotchless: Bool) -> CGSize {
        CGSize(
            width: baseWidth + (isNotchless ? alertExtraWidth.notchless : alertExtraWidth.notch),
            height: baseHeight + alertExtraHeight
        )
    }

    // MARK: Panel desplegado

    static let panelExtraWidth: (notch: CGFloat, notchless: CGFloat) = (380, 440)
    static let panelCornerRadius: (top: CGFloat, bottom: CGFloat) = (24, 36)
    static let panelHorizontalPadding: (notch: CGFloat, notchless: CGFloat) = (42, 17)
    static let panelTopPadding: CGFloat = 6.5
    static let panelNotchlessTopInset: CGFloat = 8.5
    static let panelBottomPadding: CGFloat = 10.5
    static let headerHeight: CGFloat = 36
    static let headerSpacing: CGFloat = 8.5
    static let rowHeight: CGFloat = 42
    static let rowSpacing: CGFloat = 4.5
    static let rowCornerRadius: CGFloat = 12
    static let rowBarWidth: CGFloat = 3
    static let rowIconSize: CGFloat = 26
    static let rowActionSize: CGFloat = 24
    static let bannerHeight: CGFloat = 25
    static let bannerSpacing: CGFloat = 6.5
    static let footerHeight: CGFloat = 21
    static let footerSpacing: CGFloat = 6.5
    static let emptyStateHeight: CGFloat = 88
    static let maxPanelExtraHeight: CGFloat = 284
    static let chipCornerRadius: CGFloat = 5
    static let controlCornerRadius: CGFloat = 9

    static func panelSize(
        baseWidth: CGFloat,
        baseHeight: CGFloat,
        rows: Int,
        hasBanner: Bool,
        isNotchless: Bool
    ) -> CGSize {
        let visibleRows = max(0, min(rows, maxVisibleRows))
        let listHeight = visibleRows == 0
            ? emptyStateHeight
            : CGFloat(visibleRows) * rowHeight + CGFloat(visibleRows - 1) * rowSpacing
        let bannerBlock = hasBanner ? bannerHeight + bannerSpacing : 0
        let extra = panelTopPadding
            + headerHeight + headerSpacing
            + bannerBlock
            + listHeight
            + footerSpacing + footerHeight
            + panelBottomPadding
        return CGSize(
            width: baseWidth + (isNotchless ? panelExtraWidth.notchless : panelExtraWidth.notch),
            height: baseHeight + min(extra, maxPanelExtraHeight)
        )
    }

    /// Alto disponible para la lista una vez descontados cabecera, pie y aviso; es el que debe usar
    /// el `ScrollView` para que el recorte coincida con `panelSize`.
    static func listHeight(rows: Int, hasBanner: Bool) -> CGFloat {
        let visibleRows = max(0, min(rows, maxVisibleRows))
        guard visibleRows > 0 else { return emptyStateHeight }
        let natural = CGFloat(visibleRows) * rowHeight + CGFloat(visibleRows - 1) * rowSpacing
        let fixed = panelTopPadding + headerHeight + headerSpacing
            + (hasBanner ? bannerHeight + bannerSpacing : 0)
            + footerSpacing + footerHeight + panelBottomPadding
        return min(natural, maxPanelExtraHeight - fixed)
    }

    static let hoverAnimationResponse: Double = 0.3
    static let hoverAnimationDamping: Double = 0.86
}
