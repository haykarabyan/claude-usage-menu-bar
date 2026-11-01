import AppKit

/// What the menu bar title shows next to the gauge icon.
enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case session, week, both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .session: "Current session"
        case .week: "This week"
        case .both: "Session and week"
        }
    }
}

/// Renders the menu bar item: two stacked mini bars (session on top, week below)
/// followed by the usage percentage. Drawn as a template image so it adapts to
/// light/dark menu bars and the selected state.
enum MenuBarIcon {
    static func image(usage: UsageResponse?, display: MenuBarDisplay) -> NSImage {
        let session = usage?.fiveHour?.utilization
        let week = usage?.sevenDay?.utilization
        let text = title(session: session, week: week, display: display)

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = (text as NSString).size(withAttributes: attributes)

        let barWidth: CGFloat = 14
        let barHeight: CGFloat = 4
        let barGap: CGFloat = 3
        let spacing: CGFloat = 4
        let height: CGFloat = 18
        let size = NSSize(width: ceil(barWidth + spacing + textSize.width), height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            let barsTop = (height + barHeight * 2 + barGap) / 2
            drawBar(fraction: session, in: NSRect(x: 0, y: barsTop - barHeight, width: barWidth, height: barHeight))
            drawBar(fraction: week, in: NSRect(x: 0, y: barsTop - barHeight * 2 - barGap, width: barWidth, height: barHeight))

            let textOrigin = NSPoint(x: barWidth + spacing, y: (height - textSize.height) / 2)
            (text as NSString).draw(at: textOrigin, withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Claude usage \(text)"
        return image
    }

    private static func title(session: Double?, week: Double?, display: MenuBarDisplay) -> String {
        func format(_ value: Double?) -> String { value.map(Formatting.percent) ?? "–" }
        switch display {
        case .session: return format(session)
        case .week: return format(week)
        case .both: return "\(format(session)) · \(format(week))"
        }
    }

    private static func drawBar(fraction percent: Double?, in rect: NSRect) {
        let radius = rect.height / 2
        NSColor.black.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        guard let percent, percent > 0 else { return }
        let fraction = min(percent / 100, 1)
        var filled = rect
        filled.size.width = max(rect.width * fraction, rect.height)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}
