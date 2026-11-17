import SwiftUI

/// A glyph drawn from Paper's own SVG data, so an icon in the app is the icon in the design and
/// not the nearest SF Symbol. A glyph is a square view box and a few layers (stroked or filled
/// paths, circles, rounded rectangles); `PaperIcon` draws it at any size in any colour.
///
/// Adding one: copy the `<svg>` from Paper (`get_jsx`), keep its `viewBox` side as `box` and each
/// child as a layer with its `strokeWidth`:
///
///     static let menu = PaperGlyph(box: 20, [.stroke("M3.5 7H16.5M3.5 13H11.5", 1.8)])
struct PaperGlyph: Sendable {
    enum Paint: Sendable { case stroke(CGFloat), fill, fillAndStroke(CGFloat) }
    struct Layer: Sendable {
        let path: Path
        let paint: Paint

        /// An SVG `<path d="…">`, stroked with round caps and joins.
        static func stroke(_ d: String, _ width: CGFloat) -> Layer { Layer(path: SVGPath.path(d), paint: .stroke(width)) }
        /// An SVG `<path d="…">`, filled.
        static func fill(_ d: String) -> Layer { Layer(path: SVGPath.path(d), paint: .fill) }
        /// Filled and stroked in the same colour (Paper's Navigate arrow).
        static func solid(_ d: String, _ width: CGFloat) -> Layer { Layer(path: SVGPath.path(d), paint: .fillAndStroke(width)) }
        /// An SVG `<circle>`; `width` nil fills it.
        static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ width: CGFloat? = nil) -> Layer {
            Layer(path: Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                  paint: width.map { .stroke($0) } ?? .fill)
        }
        /// An SVG `<rect rx>`, stroked.
        static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, rx: CGFloat, _ width: CGFloat) -> Layer {
            Layer(path: Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: rx, style: .circular),
                  paint: .stroke(width))
        }
    }
    /// The side of the SVG's square view box.
    let box: CGFloat
    let layers: [Layer]

    init(box: CGFloat, _ layers: [Layer]) {
        self.box = box
        self.layers = layers
    }
}

/// Draws a `PaperGlyph`. `size` is the drawn side in points (Paper's `width`/`height`); strokes
/// scale with it as an SVG's do. Decorative: the control that wears it carries the label.
struct PaperIcon: View {
    let glyph: PaperGlyph
    var size: CGFloat = 20
    var color: Color = Theme.foreground
    /// True where the icon sits beside text that grows with Dynamic Type (a drawer row).
    var scales = false
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1

    init(_ glyph: PaperGlyph, size: CGFloat = 20, color: Color = Theme.foreground, scales: Bool = false) {
        self.glyph = glyph
        self.size = size
        self.color = color
        self.scales = scales
    }

    var body: some View {
        let side = scales ? size * min(typeScale, 1.6) : size
        let factor = side / glyph.box
        let transform = CGAffineTransform(scaleX: factor, y: factor)
        ZStack {
            ForEach(Array(glyph.layers.enumerated()), id: \.offset) { _, layer in
                let path = layer.path.applying(transform)
                switch layer.paint {
                case .fill:
                    path.fill(color)
                case .stroke(let width):
                    path.stroke(color, style: StrokeStyle(lineWidth: width * factor, lineCap: .round, lineJoin: .round))
                case .fillAndStroke(let width):
                    path.fill(color)
                    path.stroke(color, style: StrokeStyle(lineWidth: width * factor, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

// MARK: - Paper's glyphs

extension PaperGlyph {
    // Chrome (main file: 18 Schedule, 20 Jobs, DS primitives).
    /// The menu circle's two lines, the lower one short.
    static let menu = PaperGlyph(box: 20, [.stroke("M3.5 7H16.5M3.5 13H11.5", 1.8)])
    /// The brand + circle (draw at 20, white).
    static let plus = PaperGlyph(box: 20, [.stroke("M10 4V16M4 10H16", 2)])
    /// The drawer's quieter + (draw at 18).
    static let plusLight = PaperGlyph(box: 18, [.stroke("M9 3.5V14.5M3.5 9H14.5", 1.8)])
    /// The search field's magnifier (draw at 18).
    static let search = PaperGlyph(box: 20, [.circle(9, 9, 5.5, 1.8), .stroke("M13.5 13.5L17 17", 1.8)])
    /// The drawer search's magnifier (draw at 16).
    static let searchSmall = PaperGlyph(box: 16, [.circle(7, 7, 4.8, 1.5), .stroke("M10.6 10.6L13.5 13.5", 1.5)])
    /// The filter circle's three shortening lines (draw at 16).
    static let filter = PaperGlyph(box: 16, [.stroke("M2.5 5H13.5M4.5 8H11.5M6.5 11H9.5", 1.6)])
    /// A filter chip's × (draw at 11).
    static let close = PaperGlyph(box: 12, [.stroke("M3 3L9 9M9 3L3 9", 1.6)])
    /// Navigate's solid arrow (draw at 16, white).
    static let navigate = PaperGlyph(box: 14, [.solid("M12.5 1.5L6.5 12.5L5.5 8.5L1.5 7.5L12.5 1.5Z", 1.2)])
    /// The call circle's handset (draw at 20).
    static let phone = PaperGlyph(box: 16, [.stroke("M3 2.5C2.7 2.5 2.5 2.7 2.5 3C2.5 8.8 7.2 13.5 13 13.5C13.3 13.5 13.5 13.3 13.5 13V10.8C13.5 10.5 13.3 10.3 13 10.2L10.8 9.5C10.6 9.4 10.3 9.5 10.2 9.7L9.6 10.6C8 9.8 6.2 8 5.4 6.4L6.3 5.8C6.5 5.7 6.6 5.4 6.5 5.2L5.8 3C5.7 2.7 5.5 2.5 5.2 2.5H3Z", 1.3)])
    /// The message circle's bubble (draw at 20).
    static let message = PaperGlyph(box: 16, [.stroke("M2.5 8C2.5 5 5 3 8 3C11 3 13.5 5 13.5 8C13.5 11 11 13 8 13C7.2 13 6.5 12.9 5.8 12.6L3 13.3L3.8 11C3 10.2 2.5 9.2 2.5 8Z", 1.3)])

    // The detail header (21 Job): back, share and "…" in 44pt card circles, drawn at 20.
    static let back = PaperGlyph(box: 20, [.stroke("M12 4.5L6.5 10L12 15.5", 1.8)])
    static let share = PaperGlyph(box: 16, [.stroke("M8 10V2M8 2L5 5M8 2L11 5", 1.5),
                                            .stroke("M3 8V12.5C3 13.1 3.4 13.5 4 13.5H12C12.6 13.5 13 13.1 13 12.5V8", 1.5)])
    static let more = PaperGlyph(box: 16, [.circle(3.5, 8, 1.2), .circle(8, 8, 1.2), .circle(12.5, 8, 1.2)])
    /// A chip's small down chevron (draw at 12).
    static let chevronDown = PaperGlyph(box: 12, [.stroke("M3 4.5L6 7.5L9 4.5", 1.5)])

    /// Paper's glyph for a round chrome button, looked up by the SF Symbol call sites already pass
    /// to `PaperCircleButton` / `PaperCircleLabel`, so every "…", share, back, call and message
    /// circle in the app draws Paper's own mark. Nil keeps the symbol.
    static func chrome(symbol: String) -> PaperGlyph? {
        switch symbol {
        case "chevron.left": .back
        case "ellipsis": .more
        case "square.and.arrow.up": .share
        case "phone": .phone
        case "bubble.left", "message": .message
        case "magnifyingglass": .search
        case "line.3.horizontal.decrease": .filter
        case "line.3.horizontal": .menu
        default: nil
        }
    }

    // The drawer (Navigation file 29N / 57N / 58N), all drawn at 18 with a 1.5 stroke.
    static let bell = PaperGlyph(box: 18, [.stroke("M4.5 12.5V8a4.5 4.5 0 0 1 9 0v4.5l1.2 1.5H3.3ZM7.3 15.5a1.8 1.8 0 0 0 3.4 0", 1.5)])
    static let gear = PaperGlyph(box: 18, [.circle(9, 9, 2.5, 1.5),
                                           .stroke("M9 2v2M9 14v2M2 9h2M14 9h2M4 4l1.4 1.4M12.6 12.6L14 14M4 14l1.4-1.4M12.6 5.4L14 4", 1.5)])
    static let dashboard = PaperGlyph(box: 18, [.rect(2.5, 2.5, 5.5, 5.5, rx: 1.2, 1.5), .rect(10, 2.5, 5.5, 5.5, rx: 1.2, 1.5),
                                                .rect(2.5, 10, 5.5, 5.5, rx: 1.2, 1.5), .rect(10, 10, 5.5, 5.5, rx: 1.2, 1.5)])
    static let calendar = PaperGlyph(box: 18, [.rect(2.5, 3.5, 13, 12, rx: 2, 1.5), .stroke("M2.5 7.5H15.5M6 2V5M12 2V5", 1.5)])
    static let jobs = PaperGlyph(box: 18, [.rect(2.5, 5, 13, 10, rx: 2, 1.5), .stroke("M6.5 5V3.5h5V5", 1.5)])
    static let money = PaperGlyph(box: 18, [.rect(2, 4.5, 14, 9, rx: 2, 1.5), .circle(9, 9, 2, 1.5)])
    /// One person: Customers on the office and owner menus.
    static let person = PaperGlyph(box: 18, [.circle(9, 6, 3, 1.5), .stroke("M3.5 15.5c.7-3 2.9-4.5 5.5-4.5s4.8 1.5 5.5 4.5", 1.5)])
    /// Two people: Team, and Customers on the technician's menu.
    static let people = PaperGlyph(box: 18, [.circle(7, 6.5, 2.5, 1.5),
                                             .stroke("M2.5 15c.6-2.6 2.4-4 4.5-4s3.9 1.4 4.5 4M12 4.5a2.3 2.3 0 0 1 0 4.4M13 11c1.4.4 2.3 1.6 2.6 3.6", 1.5)])
    static let funnel = PaperGlyph(box: 18, [.stroke("M2.5 3.5h13l-5 6v5l-3 1.5v-6.5Z", 1.5)])
    static let bubble = PaperGlyph(box: 18, [.stroke("M3 8.5C3 5.5 5.7 3 9 3S15 5.5 15 8.5 12.3 14 9 14C8.2 14 7.4 13.9 6.7 13.6L3.5 14.5L4.3 11.8C3.5 10.9 3 9.7 3 8.5Z", 1.5)])
    static let clock = PaperGlyph(box: 18, [.circle(9, 9, 6.5, 1.5), .stroke("M9 5.5V9L11.5 10.5", 1.5)])
    static let priceBook = PaperGlyph(box: 18, [.stroke("M4 2.5h8.5a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4Z", 1.5), .stroke("M4 2.5v13", 1.5)])
    static let receipt = PaperGlyph(box: 18, [.stroke("M4 2.5h10v13l-2-1.2-1.6 1.2-1.4-1.2-1.4 1.2L6 14.3 4 15.5Z", 1.5)])
    static let cube = PaperGlyph(box: 18, [.stroke("M9 2l6 3.3v7.4L9 16l-6-3.3V5.3Z M3 5.3L9 8.6l6-3.3M9 8.6V16", 1.5)])
    static let equipment = PaperGlyph(box: 18, [.rect(2.5, 4, 13, 10, rx: 1.5, 1.5), .circle(9, 9, 2.5, 1.5)])
    static let training = PaperGlyph(box: 18, [.stroke("M1.5 7L9 3.5 16.5 7 9 10.5Z M4.5 8.5V12c1.2 1.2 2.7 1.8 4.5 1.8s3.3-.6 4.5-1.8V8.5", 1.5)])
    static let truck = PaperGlyph(box: 18, [.stroke("M1.5 5h9v7h-9ZM10.5 7.5h3.5l2.5 2.5v2h-6Z", 1.5), .circle(5, 13.5, 1.5, 1.5), .circle(13, 13.5, 1.5, 1.5)])
    /// A house with its door: Properties.
    static let property = PaperGlyph(box: 18, [.stroke("M2.5 8L9 3l6.5 5v7.5h-13Z", 1.5), .stroke("M7 15.5V11h4v4.5", 1.5)])
    /// A plain house: Business settings.
    static let business = PaperGlyph(box: 18, [.stroke("M2.5 8L9 3l6.5 5v7.5h-13Z", 1.5)])
    static let shield = PaperGlyph(box: 18, [.stroke("M9 2.5l5.5 2v4.5c0 3.2-2.3 5.6-5.5 6.5-3.2-.9-5.5-3.3-5.5-6.5V4.5Z", 1.5),
                                             .stroke("M6.5 9l1.8 1.8L11.8 7.3", 1.5)])
    static let reports = PaperGlyph(box: 18, [.stroke("M3.5 15V9M7.2 15V5M10.8 15V8M14.5 15V3", 1.6)])
    static let megaphone = PaperGlyph(box: 18, [.stroke("M3 7.5v3h2.5l5 3.5v-10l-5 3.5Z", 1.5), .stroke("M13 6.5a3.5 3.5 0 0 1 0 5", 1.5)])
    /// A page with lines: Vendors and POs on the owner's menu.
    static let document = PaperGlyph(box: 18, [.stroke("M4 2.5h10v13H4Z M6.5 6h5M6.5 9h5M6.5 12h3", 1.5)])

    /// Paper's drawer glyph for a place, looked up by the SF Symbol the menu model names it with.
    /// Nil for a place Paper's menus do not draw; the caller falls back to the symbol.
    static func place(symbol: String) -> PaperGlyph? {
        switch symbol {
        case "square.grid.2x2": .dashboard
        case "calendar": .calendar
        case "briefcase": .jobs
        case "person": .person
        case "person.2": .people
        case "house": .property
        case "bubble.left": .bubble
        case "book.closed": .priceBook
        case "banknote": .money
        case "chart.bar": .reports
        case "building.2": .business
        case "clock": .clock
        case "receipt": .receipt
        case "cube": .cube
        case "graduationcap": .training
        case "line.3.horizontal.decrease": .funnel
        case "cart": .document
        case "megaphone": .megaphone
        case "box.truck": .truck
        case "wrench.and.screwdriver": .equipment
        case "checkmark.shield": .shield
        default: nil
        }
    }
}

// MARK: - SVG path data

/// Parses SVG path data (`M L H V C S Q T A Z`, absolute and relative) into a SwiftUI `Path`.
enum SVGPath {
    static func path(_ d: String) -> Path {
        var path = Path()
        var scanner = Scanner(d)
        var command: Character = "M"
        var current = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint?
        while true {
            if let next = scanner.command() { command = next } else if scanner.atEnd { break }
            let relative = command.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch command.uppercased() {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = point(x, y); start = current
                path.move(to: current)
                // Further pairs after a move are lines.
                command = relative ? "l" : "L"
                lastControl = nil
            case "L":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = point(x, y); path.addLine(to: current); lastControl = nil
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current); lastControl = nil
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current); lastControl = nil
            case "C":
                guard let x1 = scanner.number(), let y1 = scanner.number(), let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = point(x1, y1), c2 = point(x2, y2), end = point(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2; current = end
            case "S":
                guard let x2 = scanner.number(), let y2 = scanner.number(), let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(x2, y2), end = point(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2; current = end
            case "Q":
                guard let x1 = scanner.number(), let y1 = scanner.number(), let x = scanner.number(), let y = scanner.number() else { return path }
                let c = point(x1, y1), end = point(x, y)
                path.addQuadCurve(to: end, control: c)
                lastControl = c; current = end
            case "T":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                let c = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let end = point(x, y)
                path.addQuadCurve(to: end, control: c)
                lastControl = c; current = end
            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let end = point(x, y)
                addArc(to: &path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = end; lastControl = nil
            case "Z":
                path.closeSubpath()
                current = start; lastControl = nil
                // A close takes no numbers; the next token must be a command.
                if scanner.peekIsNumber { return path }
            default:
                return path
            }
        }
        return path
    }

    /// SVG's endpoint arc as cubic curves (spec F.6.5 and F.6.6).
    private static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat,
                               rotation: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0, p0 != p1 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = denominator == 0 ? 0 : sqrt(max(0, numerator / denominator))
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry, cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy, length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var value = acos(min(1, max(-1, length == 0 ? 1 : dot / length)))
            if ux * vy - uy * vx < 0 { value = -value }
            return value
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi } else if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let k = 4 / 3 * tan(step / 4)
        var a = theta
        func onEllipse(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi, y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func tangent(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi, y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        for _ in 0..<segments {
            let b = a + step
            let from = onEllipse(a), to = onEllipse(b), t0 = tangent(a), t1 = tangent(b)
            path.addCurve(to: to, control1: CGPoint(x: from.x + k * t0.x, y: from.y + k * t0.y),
                          control2: CGPoint(x: to.x - k * t1.x, y: to.y - k * t1.y))
            a = b
        }
    }

    private struct Scanner {
        private let chars: [Character]
        private var index = 0
        init(_ string: String) { chars = Array(string) }

        private mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n" || chars[index] == "\t" { index += 1 }
        }
        var atEnd: Bool {
            mutating get { skipSeparators(); return index >= chars.count }
        }
        var peekIsNumber: Bool {
            mutating get {
                skipSeparators()
                guard index < chars.count else { return false }
                return chars[index].isNumber || chars[index] == "-" || chars[index] == "." || chars[index] == "+"
            }
        }
        mutating func command() -> Character? {
            skipSeparators()
            guard index < chars.count, chars[index].isLetter, chars[index] != "e", chars[index] != "E" else { return nil }
            defer { index += 1 }
            return chars[index]
        }
        mutating func number() -> CGFloat? {
            skipSeparators()
            var text = ""
            var seenDot = false, seenDigit = false
            if index < chars.count, chars[index] == "-" || chars[index] == "+" { text.append(chars[index]); index += 1 }
            while index < chars.count {
                let c = chars[index]
                if c.isNumber { text.append(c); seenDigit = true; index += 1 }
                else if c == ".", !seenDot { text.append(c); seenDot = true; index += 1 }
                else { break }
            }
            guard seenDigit, let value = Double(text) else { return nil }
            return CGFloat(value)
        }
        /// An arc flag is a single 0 or 1 and may run straight into the next number.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < chars.count, chars[index] == "0" || chars[index] == "1" else { return nil }
            defer { index += 1 }
            return chars[index] == "1"
        }
    }
}
