import XCTest
import SwiftUI
import UIKit
@testable import Thorbis

@MainActor
final class AppearanceTests: XCTestCase {
    // Catches a hard-coded dark palette that ignores the device appearance.
    func testSurfacesFollowTheSystemAppearance() {
        for color in [Theme.background, Theme.surface, Theme.chrome, Theme.card, Theme.fill] {
            XCTAssertGreaterThan(luminance(resolve(color, style: .light)), 0.8)
            XCTAssertLessThan(luminance(resolve(color, style: .dark)), 0.1)
        }
    }

    // Inverse type on ink (a step badge, today's date, the listening mic) stays readable in every
    // appearance. The commit itself is the blue pill; testBrandCommitTypeIsReadable covers it.
    func testInkCommitTypeIsReadable() {
        for style: UIUserInterfaceStyle in [.light, .dark] {
            for contrast: UIAccessibilityContrast in [.normal, .high] {
                let ink = luminance(resolve(Theme.ink, style: style, contrast: contrast))
                let type = luminance(resolve(Theme.onInk, style: style, contrast: contrast))
                XCTAssertGreaterThanOrEqual((max(ink, type) + 0.05) / (min(ink, type) + 0.05), 7,
                    "Ink commit unreadable in style \(style.rawValue), contrast \(contrast.rawValue)")
            }
        }
    }

    // Paper v2: the commit and every blue or red pill set white type on `brand` or
    // `destructiveFill`; it holds 4.5:1 in every appearance, Increase Contrast included.
    func testBrandCommitTypeIsReadable() {
        let white = luminance(UIColor(red: 1, green: 1, blue: 1, alpha: 1))
        for style: UIUserInterfaceStyle in [.light, .dark] {
            for contrast: UIAccessibilityContrast in [.normal, .high] {
                for fill in [Theme.brand, Theme.destructiveFill] {
                    let ground = luminance(resolve(fill, style: style, contrast: contrast))
                    XCTAssertGreaterThanOrEqual((max(white, ground) + 0.05) / (min(white, ground) + 0.05), 4.5,
                        "White on a commit fill unreadable in style \(style.rawValue), contrast \(contrast.rawValue)")
                }
            }
        }
    }

    // Paper v2 (2026-11-16): Inter 400 to 700; heavier is bold, lighter is regular; nothing under 12.
    func testTypeRampKeepsPaperWeightsAndAFloor() {
        for weight: Font.Weight in [.regular, .medium, .semibold, .bold] {
            XCTAssertEqual(Theme.allowed(weight), weight)
        }
        for heavy: Font.Weight in [.heavy, .black] {
            XCTAssertEqual(Theme.allowed(heavy), .bold)
        }
        for light: Font.Weight in [.ultraLight, .thin, .light] {
            XCTAssertEqual(Theme.allowed(light), .regular)
        }
        XCTAssertEqual(Theme.minimumSize, 12)
    }

    // Paper's electric blue (#2F6BFF, drawn one step darker as #2F6AFF, green 6B to 6A, so white
    // type holds 4.5:1).
    // The web keeps its own accent (#3A6AE0); neither client is repainted to the other's blue.
    func testBrandIsPaperBlue() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(UIColor(Theme.brand).getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertEqual(Int((r * 255).rounded()), 0x2F)
        XCTAssertEqual(Int((g * 255).rounded()), 0x6A)
        XCTAssertEqual(Int((b * 255).rounded()), 0xFF)
    }

    // Paper v2: Paper's own sizes (rows 16, subtitles 14, labels 13, sheet titles 17/22) and a
    // 34pt bold title on every screen; customer-facing presentation keeps its 17pt floor.
    func testEverySizeLandsOnTheRamp() {
        let ramp: Set<CGFloat> = [12, 13, 14, 15, 16, 17, 20, 22, 24, 28, 30, 34]
        for size in stride(from: CGFloat(8), through: 40, by: 1) {
            XCTAssertTrue(ramp.contains(Theme.onRamp(size)), "\(size) snapped to \(Theme.onRamp(size))")
        }
        XCTAssertEqual(Theme.onRamp(14), 14)
        XCTAssertEqual(Theme.onRamp(15), 15)
        XCTAssertEqual(Theme.onRamp(16), 16)
        XCTAssertEqual(Theme.onRamp(17), 17)
        XCTAssertEqual(Theme.onRamp(22), 22)
        XCTAssertEqual(Theme.onRamp(30), 30, "Paper draws record titles at 30")
        XCTAssertEqual(Theme.onRamp(28), 28)
        XCTAssertEqual(Theme.onRamp(34), 34)
        XCTAssertEqual(Theme.customerRamp(17), 17)
        XCTAssertEqual(Theme.customerRamp(34), 34)
    }

    // Catches unreadable labels on cards/fields, including Increase Contrast.
    func testInformationalTextIsReadableOnEverySurface() {
        for style: UIUserInterfaceStyle in [.light, .dark] {
            for contrast: UIAccessibilityContrast in [.normal, .high] {
                for foreground in [Theme.foreground, Theme.muted, Theme.subtle] {
                    for background in [Theme.background, Theme.surface, Theme.chrome, Theme.card, Theme.fill, Theme.field] {
                        let text = luminance(resolve(foreground, style: style, contrast: contrast))
                        let surface = luminance(resolve(background, style: style, contrast: contrast))
                        XCTAssertGreaterThanOrEqual((max(text, surface) + 0.05) / (min(text, surface) + 0.05), 4.5,
                            "Unreadable text in style \(style.rawValue), contrast \(contrast.rawValue)")
                    }
                }
            }
        }
    }

    // Redesign 2026-10-31: status words stay readable on the ground, the well and their own chip tint.
    func testStatusTextIsReadableOnItsGrounds() {
        let pairs: [(Color, Color)] = [
            (Theme.statusScheduledText, Theme.statusScheduledSurface), (Theme.statusDispatchedText, Theme.statusDispatchedSurface),
            (Theme.statusInProgressText, Theme.statusInProgressSurface), (Theme.statusDoneText, Theme.statusDoneSurface),
            (Theme.statusAttentionText, Theme.statusAttentionSurface), (Theme.statusInvoicedText, Theme.statusInvoicedSurface)
        ]
        for style: UIUserInterfaceStyle in [.light, .dark] {
            for contrast: UIAccessibilityContrast in [.normal, .high] {
                for (text, tint) in pairs {
                    for ground in [Theme.background, Theme.card, tint] {
                        let a = luminance(resolve(text, style: style, contrast: contrast))
                        let b = luminance(resolve(ground, style: style, contrast: contrast))
                        XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5,
                            "Unreadable status text in style \(style.rawValue), contrast \(contrast.rawValue)")
                    }
                }
            }
        }
    }

    private func resolve(_ color: Color, style: UIUserInterfaceStyle,
                         contrast: UIAccessibilityContrast = .normal) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(accessibilityContrast: contrast)
        ]))
    }

    private func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
        func linear(_ value: CGFloat) -> Double {
            let c = Double(value)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
