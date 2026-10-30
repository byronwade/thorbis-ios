import Foundation

/// What changed in each update, shown once in the What's new sheet (design.thorbis.com MA-19..MA-22).
///
/// How to add notes: the pull request that changes what people see adds a new entry at the TOP
/// of `all`, with an id that is never reused. Unshipped entries fold together in the sheet, so
/// two PRs in one build just means two entries. Write for the person doing the work (MA-21):
/// - `title`: what they can now do, at most 40 characters ("Mark arrived from the lock screen").
/// - `detail`: one sentence, at most 110 characters, in domain words. No ticket ids or code names.
/// - At most five highlights per entry; anything smaller goes in `fixes` as a count.
/// - `symbol` is an SF Symbol outline name. A change nobody can see gets no note.
/// `WhatsNewTests` checks every rule above.
enum ReleaseNotes {
    static let all: [ReleaseNote] = [
        ReleaseNote(
            id: "2026-10-30-owner-setup",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "person.crop.circle.badge.plus", title: "Start your company from your phone",
                      detail: "Create an account, name your company and walk through setup one step at a time."),
                .init(symbol: "square.and.arrow.down", title: "Import customers from a spreadsheet",
                      detail: "Choose a CSV from your old software, check the columns and bring everyone in."),
                .init(symbol: "person.badge.minus", title: "Remove someone from your team",
                      detail: "Long-press a person on Team to remove them. They keep their account and can be invited again."),
                .init(symbol: "house", title: "See every property in one list",
                      detail: "Properties shows each service address across your customers, with search."),
                .init(symbol: "tablecells", title: "Download reports as spreadsheets",
                      detail: "Revenue, jobs, schedule and payment reports open as Excel files you can share."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-10-30-sizes-any-order",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "ruler", title: "Sizes found however you type them",
                      detail: "Pipe 10 mm finds an item written Pipe 10mm, and the words can go in any order."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-tablet-invoice",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "doc.plaintext", title: "Invoices open from iPad Schedule",
                      detail: "On iPad, a job's invoice opens from Schedule and stays the one you picked when you come back."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-10-30-modern-pass-1",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "textformat", title: "Cleaner screens, easier numbers",
                      detail: "Amounts and times use the same clean type as the rest of the app, and the job header is lighter."),
            ],
            fixes: 2
        ),
        ReleaseNote(
            id: "2026-10-30-bottom-search",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "magnifyingglass", title: "Search from the bottom",
                      detail: "Search opens in the bar under your thumb, with recent records and results rising above it."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-10-30-bar-live",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "record.circle", title: "Your current job, one tap away",
                      detail: "The job you are on floats above the bar on every screen. Tap it to open the job."),
                .init(symbol: "arrow.triangle.2.circlepath", title: "See what is still syncing",
                      detail: "Search shows how many changes are waiting on this phone, and turns red if one needs a look."),
                .init(symbol: "hand.tap", title: "Hold + or Search for shortcuts",
                      detail: "Hold + to start a job, estimate or customer. Hold Search for what you opened last."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-bottom-bar-menu",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "dock.rectangle", title: "Get around from the bottom bar",
                      detail: "Your places sit in a bar at the bottom. Tap the last one again to open every place."),
                .init(symbol: "building.2", title: "Switch business from the menu",
                      detail: "Your business name sits on top of the menu. Tap it to switch to another business or add one."),
                .init(symbol: "arrow.up.arrow.down", title: "Arrange your bar and menu",
                      detail: "Tap the sliders in the menu, then drag places to reorder them or move them into the bar."),
                .init(symbol: "magnifyingglass", title: "Search in one tap",
                      detail: "Search sits next to New job at the bottom and opens ready to type."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-menu-layout",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "sidebar.left", title: "A menu with room to tap",
                      detail: "Places are a plain list. Pull the menu down to search. Your account opens Settings."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-price-book-loads",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "book.closed", title: "Price book loads your prices",
                      detail: "The price book opens with your items. If it cannot, it says so in plain words."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-records-activity",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "chevron.right", title: "Open activity on the customer file",
                      detail: "Activity on the Records tab opens the job, estimate, invoice, contact, or location it names."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-photo-stage",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "tag", title: "Mark a photo before or after",
                      detail: "Change a saved job photo to Before, After, or Other without taking it again."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-search-pages",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "text.magnifyingglass", title: "Search keeps later matches",
                      detail: "Company search includes matches from every page the server returns."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-activity-opens",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "arrow.up.right", title: "Open the record behind activity",
                      detail: "Activity rows open the job, estimate, invoice, note, photo, contact, or location they name."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-draft-lines",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "book.closed", title: "Edit draft lines in the price book",
                      detail: "Search the price book on a draft estimate or invoice, then change the quantity, price, or remove the line."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-customer-records",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "rectangle.stack", title: "A customer's jobs in one place",
                      detail: "See every job's photos, notes, documents, estimates, invoices, and activity together, still grouped by job."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-menu-room",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "magnifyingglass", title: "Search sits at the top of the menu",
                      detail: "Search has its own row under the company, and the account opens Settings with room to tap."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-28-job-hours",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "clock", title: "See how long each job took",
                      detail: "A job's Details show the drive and the time on site, from On my way, Mark arrived and Wrap up."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-28-exact-model-numbers",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "number", title: "Part and model numbers match exactly",
                      detail: "Searching R-410A never shows R-420A, and R410A without the dash still finds it."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-28-job-screen",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "ellipsis.circle", title: "Every job action in one menu",
                      detail: "Pause, reschedule, assign, deposit and wrap up now live in the ••• at the top right of a job."),
                .init(symbol: "person.2", title: "Call or text any contact on the job",
                      detail: "Every contact is listed with their own Call, Text and Email, and how they like to be reached."),
                .init(symbol: "key", title: "Gate codes, dogs and parking up front",
                      detail: "Getting in shows each code on its own line. Long press a code to copy it."),
                .init(symbol: "clock.arrow.circlepath", title: "See what happened on past visits",
                      detail: "A job lists the customer's earlier visits with the office's note from each one."),
                .init(symbol: "wrench.and.screwdriver", title: "Equipment and membership on the job",
                      detail: "Units at the site, their warranty and the customer's plan show without leaving the job."),
            ],
            fixes: 3
        ),
        ReleaseNote(
            id: "2026-10-28-estimate-builder",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "magnifyingglass", title: "Find price book items as you type",
                      detail: "Search forgives typos and words in any order, and puts the items you use most first."),
                .init(symbol: "plus.circle", title: "Tap to add, tap again for one more",
                      detail: "Results stay open while you add. Type anything that isn't in the book to add it as a line."),
                .init(symbol: "line.3.horizontal", title: "Arrange Work and Materials your way",
                      detail: "Edit any line in place, drag to reorder, and undo a removed line."),
            ],
            fixes: 3
        ),
        ReleaseNote(
            id: "2026-10-28-big-money",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "dollarsign.circle", title: "Money you can read at a glance",
                      detail: "Balance due, estimate totals and payment amounts are now the biggest thing on the screen."),
                .init(symbol: "banknote", title: "Record cash or a check in three taps",
                      detail: "Collect, pick Cash or Check, Record. No extra confirm, and it remembers what you used last."),
                .init(symbol: "link", title: "Payment links stay in one sheet",
                      detail: "Creating a payment link now opens in the same sheet, so Done takes you back to the invoice."),
                .init(symbol: "arrow.up.arrow.down", title: "Amounts roll when they change",
                      detail: "Record a payment and the balance rolls down to its new amount right where you are."),
            ],
            fixes: 4
        ),
        ReleaseNote(
            id: "2026-10-28-next-step",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "arrow.forward.circle", title: "One button runs the whole job",
                      detail: "The button at the bottom of a job is always the next step, from On my way to Collect."),
                .init(symbol: "person.crop.rectangle", title: "Show an estimate in one tap",
                      detail: "Show to customer sends a new estimate and hands it over, with no separate Send step."),
                .init(symbol: "creditcard", title: "Issue and collect in one step",
                      detail: "Issuing an invoice opens payment right away, and a paid job goes back to Wrap up."),
            ],
            fixes: 3
        ),
        ReleaseNote(
            id: "2026-10-28-whats-new",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "sparkles", title: "See what changed after each update",
                      detail: "This sheet shows once after an update. Find it again any time in Settings."),
                .init(symbol: "magnifyingglass", title: "Find invoices by customer or number",
                      detail: "Search on Invoices now matches the customer's name and the invoice number."),
                .init(symbol: "arrow.clockwise", title: "Try again when a list fails to load",
                      detail: "Estimates, invoices, closeout and follow-ups offer Try again instead of a dead end."),
                .init(symbol: "hand.tap", title: "A tap you can feel when work is done",
                      detail: "Completing, sending, approving and getting paid now confirm with a light tap."),
                .init(symbol: "figure.walk.motion", title: "Calmer motion with Reduce Motion on",
                      detail: "Every animation now follows the Reduce Motion setting on your phone."),
            ],
            fixes: 6
        ),
    ]
}

struct ReleaseNote: Identifiable, Equatable, Sendable {
    /// Stable and never reused: the sheet remembers which ids a person has seen.
    let id: String
    /// The day the change merged, as yyyy-MM-dd.
    let date: String
    let highlights: [Highlight]
    /// Smaller fixes, shown only as a count.
    var fixes = 0

    struct Highlight: Equatable, Sendable {
        let symbol: String
        let title: String
        let detail: String
    }

    static let maxTitle = 40
    static let maxDetail = 110
    static let maxHighlights = 5

    /// Noon UTC, so the label shows the same day in every US time zone.
    var day: Date? { try? Date("\(date)T12:00:00Z", strategy: .iso8601) }

    /// "Oct 28"
    var dayLabel: String { day?.formatted(.dateTime.month(.abbreviated).day()) ?? date }
}
