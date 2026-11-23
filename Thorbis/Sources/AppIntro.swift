import SwiftUI

// Paper 01–03: the three-page app intro shown once, before Login, on a fresh install.
// Static: no server, no account. The cards are illustrations, hidden from VoiceOver so their
// sample names and amounts are never read out as real work.

/// Whether the intro still needs showing. A "seen" flag on the phone, plus a returning-user
/// guard: anyone who has ever signed in on this install (SessionController writes its
/// explicit-sign-out key on every sign-in and sign-out) never sees it, even after an update.
enum AppIntroGate {
    static let seenKey = "thorbis.appIntro.seen"
    /// SessionController.explicitSignOutKey (private there); present once anyone has signed in or out.
    static let returningUserKey = "thorbis.session.explicitlySignedOut"

    static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: seenKey) && defaults.object(forKey: returningUserKey) == nil
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: seenKey)
    }
}

/// The intro's payment line. It names Tap to Pay only when this build is allowed to take it
/// (TapToPayReadiness.buildEnabled, the ThorbisTapToPayEnabled key in Info.plist). Otherwise it
/// lists the ways the collect screen offers in every build: the code to scan, the texted pay
/// link, cash and check.
enum AppIntroCopy {
    static func paymentMessage(tapToPayEnabled: Bool) -> String {
        tapToPayEnabled
            ? "Tap to Pay, a code to scan, cash or check — collect payment before you leave the job."
            : "A code to scan, a texted pay link, cash or check — collect payment before you leave the job."
    }
}

/// How the person left the intro. Every exit ends at Login; `getStarted` lets the host open
/// sign-up there if it wants to.
enum AppIntroExit: Equatable {
    case skip
    case getStarted
    case signIn
}

/// Paper 01–03. Swipe or press Next; Skip on the first two pages; the last page ends with
/// Get started and "Already have an account? Sign in". Marks the intro seen on any exit.
struct AppIntroView: View {
    let onFinish: (AppIntroExit) -> Void
    @State private var page: Int

    /// `startPage` is for screenshots of the second and third pages.
    init(startPage: Int = 0, onFinish: @escaping (AppIntroExit) -> Void) {
        self.onFinish = onFinish
        _page = State(initialValue: startPage)
    }
    @Environment(\.horizontalSizeClass) private var sizeClass

    private static let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            // Paper: Skip at the trailing edge, 44 tall, 20 from the edge; the last page keeps the room.
            HStack {
                Spacer()
                if page < Self.pageCount - 1 {
                    Button { finish(.skip) } label: {
                        Text("Skip").font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("intro-skip")
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 20)

            TabView(selection: $page) {
                IntroPage(title: "Run your day from the field",
                          message: "Dispatch, navigation, and job status — all in your pocket, updated the moment things change.") {
                    IntroTodayCard()
                }
                .tag(0)
                IntroPage(title: "See the whole job, not just the ticket",
                          message: "Estimates, invoices, photos, and history — everything about a job lives in one place.") {
                    IntroJobCard()
                }
                .tag(1)
                IntroPage(title: "Get paid\non the spot",
                          message: AppIntroCopy.paymentMessage(tapToPayEnabled: TapToPayReadiness.buildEnabled)) {
                    IntroPaymentCard()
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            IntroPageDots(count: Self.pageCount, current: page)
                .padding(.top, 24).padding(.bottom, 4)

            VStack(spacing: 10) {
                Button {
                    if page < Self.pageCount - 1 {
                        withAnimation(.easeOut(duration: 0.25)) { page += 1 }
                    } else {
                        finish(.getStarted)
                    }
                } label: {
                    Text(page < Self.pageCount - 1 ? "Next" : "Get started").inkCommit()
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("intro-next")

                if page == Self.pageCount - 1 {
                    Button { finish(.signIn) } label: {
                        HStack(spacing: 5) {
                            Text("Already have an account?").font(Theme.font(14)).foregroundStyle(Theme.muted)
                            Text("Sign in").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("intro-sign-in")
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.top, 16).padding(.bottom, 8)
        }
        .frame(maxWidth: 470)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, sizeClass == .regular ? 40 : 0)
        .background(Theme.canvas)
    }

    private func finish(_ exit: AppIntroExit) {
        AppIntroGate.markSeen()
        onFinish(exit)
    }
}

/// One intro page: the illustration centred in the space left, then the 34 Bold title and the
/// 15 muted line, 20 from the edge.
private struct IntroPage<Illustration: View>: View {
    let title: String
    let message: String
    @ViewBuilder var illustration: Illustration

    var body: some View {
        VStack(spacing: 0) {
            VStack { illustration }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, PaperCardMetrics.margin).padding(.vertical, 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(Theme.font(34, weight: .bold)).tracking(-0.85)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 8)
        }
    }
}

/// The 18×6 brand pill for the current page, 6pt dots for the rest.
struct IntroPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.brand : Theme.muted.opacity(0.6))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

// MARK: - Illustrations (static, decorative)

/// The shared illustration card: Paper's card on the canvas, radius 20.
private struct IntroCard<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    var top: CGFloat = 18
    var bottom: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: alignment, spacing: 2) { content }
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            .padding(.horizontal, 18)
            .padding(.top, top).padding(.bottom, bottom)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Paper 01: Today, the next job in brand blue, three stops with their status dots.
private struct IntroTodayCard: View {
    var body: some View {
        IntroCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(Theme.font(22, weight: .bold)).foregroundStyle(Theme.foreground)
                Spacer()
                Text("Tue, Jul 21").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next job · 9:00 AM").font(Theme.font(13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.8))
                Text("AC not cooling — Rivera").font(Theme.font(16, weight: .semibold)).foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            stop("10:30", "Maintenance · Patel", Theme.statusDone)
            stop("12:15", "Furnace install · Chen", Theme.brand)
            stop("2:00", "Estimate · Brooks", Theme.statusInProgress)
        }
    }

    private func stop(_ time: String, _ title: String, _ dot: Color) -> some View {
        HStack(spacing: 12) {
            Text(time).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle)
                .frame(width: 56, alignment: .leading)
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 46)
        .padding(.horizontal, 2)
    }
}

/// Paper 02: a job with its tabs, two facts and the estimate action.
private struct IntroJobCard: View {
    var body: some View {
        IntroCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("JOB-2481 · HVAC").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                Text("AC not cooling").font(Theme.font(22, weight: .bold)).foregroundStyle(Theme.foreground)
            }
            .padding(.bottom, 12)
            HStack(spacing: 6) {
                chip("Arrived", fill: Theme.successSurface, type: Theme.success)
                chip("Estimate", fill: Theme.fill, type: Theme.foreground)
                chip("Photos", fill: Theme.fill, type: Theme.foreground)
                chip("History", fill: Theme.fill, type: Theme.foreground)
            }
            .padding(.bottom, 14)
            fact("Property", "214 Rivera Ln, Unit B")
            fact("Invoice", "$1,240.00")
                .padding(.bottom, 14)
            Text("Create estimate").paperButton(.card, tone: .tinted, fills: true)
                .padding(.bottom, 8)
        }
    }

    private func chip(_ word: String, fill: Color, type: Color) -> some View {
        Text(word).font(Theme.font(13, weight: .medium)).foregroundStyle(type)
            .lineLimit(1)
            .padding(.horizontal, 11).frame(height: 28)
            .background(fill, in: Capsule())
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label).font(Theme.font(14)).foregroundStyle(Theme.muted).frame(width: 96, alignment: .leading)
            Text(value).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 40)
    }
}

/// Paper 03: the amount due over the tap-to-pay rings.
private struct IntroPaymentCard: View {
    var body: some View {
        IntroCard(alignment: .center, top: 32, bottom: 32) {
            VStack(spacing: 6) {
                Text("Amount due").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                Text("$46.80").font(Theme.font(34, weight: .bold)).foregroundStyle(Theme.foreground)
            }
            .padding(.bottom, 24)
            ZStack {
                Circle().fill(Theme.brandSurface).frame(width: 104, height: 104)
                Circle().fill(Theme.brand.opacity(0.18)).frame(width: 72, height: 72)
                Circle().fill(Theme.brand).frame(width: 44, height: 44)
            }
            Text("Hold card near your phone").font(Theme.font(14)).foregroundStyle(Theme.muted)
                .padding(.top, 20)
        }
    }
}
