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

    // design.thorbis.com MA-08: the ink commit's inverse type stays readable in every appearance.
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

    // design.thorbis.com MA-09: weights 400 and 500 only, nothing under 12.
    func testTypeRampKeepsTwoWeightsAndAFloor() {
        for heavy: Font.Weight in [.semibold, .bold, .heavy, .black] {
            XCTAssertEqual(Theme.allowed(heavy), .medium)
        }
        XCTAssertEqual(Theme.allowed(.regular), .regular)
        XCTAssertEqual(Theme.allowed(.medium), .medium)
        XCTAssertEqual(Theme.minimumSize, 12)
    }

    // Catches unreadable labels on cards/fields, including Increase Contrast.
    func testInformationalTextIsReadableOnEverySurface() {
        for style: UIUserInterfaceStyle in [.light, .dark] {
            for contrast: UIAccessibilityContrast in [.normal, .high] {
                for foreground in [Theme.foreground, Theme.muted, Theme.subtle] {
                    for background in [Theme.background, Theme.surface, Theme.chrome, Theme.card, Theme.fill] {
                        let text = luminance(resolve(foreground, style: style, contrast: contrast))
                        let surface = luminance(resolve(background, style: style, contrast: contrast))
                        XCTAssertGreaterThanOrEqual((max(text, surface) + 0.05) / (min(text, surface) + 0.05), 4.5,
                            "Unreadable text in style \(style.rawValue), contrast \(contrast.rawValue)")
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
