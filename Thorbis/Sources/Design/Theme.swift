import SwiftUI
import ThorbisCore

/// Thorbis semantic tokens as native colors (design.thorbis.com Surfaces and Color,
/// packages/ui/src/tokens.css). Each name is an asset-catalog color with light,
/// dark and Increase Contrast variants, so the system resolves appearance (HIG-010).
/// Views use these names only: no raw colors in screens.
enum Theme {
    /// Near-black void (dark) or cream (light). Never a working surface.
    static let canvas = Color("Canvas")
    static let chrome = Color("Chrome")
    /// The sheet: where work happens. Brighter than chrome.
    static let sheet = Color("Sheet")
    /// A field is a well, one step darker than the sheet.
    static let field = Color("Field")
    static let subtle = Color("Subtle")
    static let selected = Color("Selected")

    static let ink = Color("Ink")
    static let inkSecondary = Color("InkSecondary")
    static let inkQuiet = Color("InkQuiet")
    static let inkInverse = Color("InkInverse")

    static let rim = Color("RimDecorative")
    static let rimInteractive = Color("RimInteractive")
    static let rimStrong = Color("RimStrong")

    /// Electric blue: a pointer for focus, selection, links and brand. Never a wash or a commit fill.
    static let accent = Color("AccentColor")
    static let destructive = Color("Destructive")

    static let success = Color("StatusSuccess")
    static let warning = Color("StatusWarning")
    static let danger = Color("StatusDanger")
    static let info = Color("StatusInfo")

    /// design.thorbis.com Radius: commit 10, sheet 14, chips and icon-only controls are full.
    enum Radius {
        static let control: CGFloat = 10
        static let sheet: CGFloat = 14
        static let small: CGFloat = 8
    }

    /// The 4-point grid.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// HIG-004: every app-owned target is at least 44 × 44 points.
    static let minimumHit: CGFloat = 44
}

/// Status tone. Status is a word first, colour second; a live job can stay grey plus a word.
enum Tone {
    case neutral, info, success, warning, danger

    var color: Color {
        switch self {
        case .neutral: Theme.inkQuiet
        case .info: Theme.info
        case .success: Theme.success
        case .warning: Theme.warning
        case .danger: Theme.danger
        }
    }
}

extension JobStatus {
    var tone: Tone {
        switch self {
        case .enRoute, .arrived, .inProgress: .info
        case .paused: .warning
        case .completed: .success
        case .canceled: .danger
        case .scheduled, .dispatched, .unknown: .neutral
        }
    }

    var symbol: String {
        switch self {
        case .scheduled: "calendar"
        case .dispatched: "paperplane"
        case .enRoute: "car"
        case .arrived: "mappin.and.ellipse"
        case .inProgress: "wrench.and.screwdriver"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle"
        case .canceled: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    var label: String { Format.status(self) }
}

extension EstimateStatus {
    var tone: Tone {
        switch self {
        case .approved: .success
        case .declined: .danger
        case .sent: .info
        case .draft, .unknown: .neutral
        }
    }

    var symbol: String {
        switch self {
        case .draft: "pencil.circle"
        case .sent: "paperplane"
        case .approved: "checkmark.circle"
        case .declined: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }
}

extension InvoiceStatus {
    var tone: Tone {
        switch self {
        case .paid: .success
        case .issued: .info
        case .void: .danger
        case .draft, .unknown: .neutral
        }
    }

    var symbol: String {
        switch self {
        case .draft: "pencil.circle"
        case .issued: "paperplane"
        case .paid: "checkmark.circle"
        case .void: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }
}

/// System, Light or Dark. Persisted; never reset on navigation.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
