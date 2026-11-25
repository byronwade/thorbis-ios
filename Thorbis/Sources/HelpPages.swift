import SwiftUI

// Paper 98C (Guided tour) and P5 (Legal page). Both are static: no server.
//
// 98C is a coach mark over the real screen: the screen dims, the control being explained keeps a
// brand ring, and a card under (or over) it says what it does, with Skip tour, Back and Next.
// Screens mark their controls with `.guidedTourTarget("id")`; the screen's root shows a tour with
// `.guidedTour(tour, onEnd:)`. Paper draws one step of the "Your first job" tour; the other
// steps are not designed yet, so only that step ships here (`GuidedTour.firstJobScheduleViews`).
//
// P5 has no artboard in the Paper files and the app holds no legal texts or legal URLs, so the
// legal page draws the text it is given, verbatim. It never turns words into links and never
// opens a URL (AGENTS.md: no arbitrary URL opening).

// MARK: - 98C Guided tour

struct GuidedTourStep: Identifiable, Equatable {
    let id: String
    /// The `.guidedTourTarget` id of the control this step explains; nil centres the card.
    let target: String?
    let title: String
    let message: String
}

struct GuidedTour: Equatable {
    /// "Your first job" — shown before "· step 2 of 5".
    let name: String
    let steps: [GuidedTourStep]

    /// Paper 98C's designed step: the Today / Week / Map switch on Schedule.
    static let firstJobScheduleViews = GuidedTourStep(
        id: "first-job-schedule-views", target: "schedule-views",
        title: "Switch how you see your day",
        message: "Today lists your stops in order. Week shows what's coming. Map shows every stop and the drive between them.")
}

struct GuidedTourTargetKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Names a control a guided tour can point at.
    func guidedTourTarget(_ id: String) -> some View {
        anchorPreference(key: GuidedTourTargetKey.self, value: .bounds) { [id: $0] }
    }

    /// Shows `tour` over this screen while it is non-nil; `onEnd` runs on Skip tour or the last Next.
    func guidedTour(_ tour: GuidedTour?, onEnd: @escaping () -> Void) -> some View {
        overlayPreferenceValue(GuidedTourTargetKey.self) { anchors in
            if let tour, !tour.steps.isEmpty {
                GeometryReader { proxy in
                    GuidedTourOverlay(tour: tour, anchors: anchors, proxy: proxy, onEnd: onEnd)
                }
                .ignoresSafeArea()
            }
        }
    }
}

private struct GuidedTourOverlay: View {
    let tour: GuidedTour
    let anchors: [String: Anchor<CGRect>]
    let proxy: GeometryProxy
    let onEnd: () -> Void
    @State private var index = 0

    private var step: GuidedTourStep { tour.steps[min(index, tour.steps.count - 1)] }

    private var target: CGRect? {
        guard let id = step.target, let anchor = anchors[id] else { return nil }
        return proxy[anchor]
    }

    var body: some View {
        let hole = target?.insetBy(dx: -6, dy: -6)
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: proxy.size))
                if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 18, height: 18)) }
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .contentShape(Rectangle())
            .onTapGesture {}
            .accessibilityHidden(true)

            if let hole {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.brand, lineWidth: 2)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                    .accessibilityHidden(true)
            }

            card
                .frame(width: max(0, min(proxy.size.width - 32, 470)))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cardAlignment(hole))
                .padding(.top, cardTop(hole))
                .padding(.bottom, cardBottom(hole))
        }
        .animation(.easeOut(duration: 0.2), value: index)
    }

    /// Under the control when it sits in the top half, over it otherwise, centred without one.
    private func cardAlignment(_ hole: CGRect?) -> Alignment {
        guard let hole else { return .center }
        return hole.midY < proxy.size.height / 2 ? .top : .bottom
    }

    private func cardTop(_ hole: CGRect?) -> CGFloat {
        guard let hole, hole.midY < proxy.size.height / 2 else { return 0 }
        return hole.maxY + 12
    }

    private func cardBottom(_ hole: CGRect?) -> CGFloat {
        guard let hole, hole.midY >= proxy.size.height / 2 else { return 0 }
        return max(0, proxy.size.height - hole.minY + 12)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(tour.name) · step \(index + 1) of \(tour.steps.count)")
                    .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                    .accessibilityIdentifier("tour-step")
                Spacer(minLength: 8)
                if tour.steps.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<tour.steps.count, id: \.self) { dot in
                            Capsule()
                                .fill(dot <= index ? Theme.brand : Theme.muted.opacity(0.6))
                                .frame(width: dot == index ? 18 : 6, height: 6)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(Theme.font(20, weight: .bold)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(step.message)
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { onEnd() } label: {
                    Text("Skip tour").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tour-skip")
                Spacer(minLength: 8)
                if index > 0 {
                    Button { index -= 1 } label: {
                        Text("Back").paperButton(.secondary, tone: .quiet)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("tour-back")
                }
                Button {
                    if index >= tour.steps.count - 1 { onEnd() } else { index += 1 }
                } label: {
                    Text(index >= tour.steps.count - 1 ? "Done" : "Next").paperButton(.secondary, tone: .brand)
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("tour-next")
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Legal links

/// The public legal pages. Sign-up and Account and data both open these.
enum LegalLinks {
    static let privacy = URL(string: "https://thorbis.com/legal/privacy")!
    static let terms = URL(string: "https://thorbis.com/legal/terms")!
}
