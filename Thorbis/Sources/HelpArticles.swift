import Foundation

// Help (Paper 98 "Help", 98A "Help article"). The articles ship inside the app and describe this
// app as it is: each one was written from the screen it explains, and names buttons by the words
// on them. There is no help desk behind this page, so there is no chat and no phone number.
// When a screen's words change, change the article that names them.

struct HelpStep: Equatable {
    /// An SF Symbol for the step's tile.
    let symbol: String
    let text: String
}

struct HelpArticle: Identifiable, Equatable, Hashable {
    let id: String
    /// Paper 98A's eyebrow ("Getting paid").
    let category: String
    let title: String
    /// One line under the title in a list and in search.
    let summary: String
    let steps: [HelpStep]
    /// The quiet line under the steps: a limit or where a setting lives.
    var note: String? = nil
    /// Words people search by that the article itself may not use ("wifi", "qr").
    var keywords: [String] = []
    var related: [String] = []

    static func == (lhs: HelpArticle, rhs: HelpArticle) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The article as plain words, for Share.
    var shareText: String {
        var lines = [title, ""]
        for (index, step) in steps.enumerated() { lines.append("\(index + 1). \(step.text)") }
        if let note { lines.append(""); lines.append(note) }
        return lines.joined(separator: "\n")
    }
}

enum HelpCatalog {
    static let categories = ["Schedule and jobs", "Estimates and invoices", "Getting paid", "Customers",
                             "Messages", "On this phone", "Menu and settings"]

    /// Paper 98 "Common questions": the three it draws, answered for this app.
    static let commonQuestions = ["invoice-issue", "text-not-received", "team-add"]

    static func article(_ id: String) -> HelpArticle? { articles.first { $0.id == id } }

    static func related(to article: HelpArticle) -> [HelpArticle] { article.related.compactMap(HelpCatalog.article) }

    static let articles: [HelpArticle] = [
        HelpArticle(
            id: "schedule-day", category: "Schedule and jobs", title: "See your day on Schedule",
            summary: "Today, Week and Map, and what the next stop offers.",
            steps: [
                HelpStep(symbol: "calendar", text: "Open Schedule from the menu. Today lists your stops in order, with your next stop first."),
                HelpStep(symbol: "map", text: "Switch to Week to see what is coming, or to Map to see every stop."),
                HelpStep(symbol: "car", text: "On your next stop, get Directions, Call the customer or tap On my way."),
                HelpStep(symbol: "hand.draw", text: "Swipe a job right to call or get directions, and left for its next step."),
            ],
            note: "People who can schedule work also see Board, which shows every tech's day.",
            keywords: ["calendar", "stops", "route", "board", "dispatch", "next stop"],
            related: ["job-start-finish", "job-new"]),
        HelpArticle(
            id: "job-start-finish", category: "Schedule and jobs", title: "Work a job from start to finish",
            summary: "One button at the bottom of the job is always the next step.",
            steps: [
                HelpStep(symbol: "briefcase", text: "Open the job. The button at the bottom is always the next step."),
                HelpStep(symbol: "car", text: "Tap On my way when you leave, I've arrived at the door, then Start work."),
                HelpStep(symbol: "camera", text: "Add photos and notes as you go. Tag photos Before or After."),
                HelpStep(symbol: "checklist", text: "Tap Wrap up and tick off what is left: photos, note, approval, signature and payment."),
                HelpStep(symbol: "checkmark.circle", text: "Tap Complete job."),
            ],
            note: "Pause job, Reschedule, Running late and Can't start are in the job's ••• menu.",
            keywords: ["status", "arrived", "en route", "closeout", "close out", "finish", "complete", "pause"],
            related: ["payment-collect", "offline"]),
        HelpArticle(
            id: "job-new", category: "Schedule and jobs", title: "Book a new job",
            summary: "Start with what is wrong, then pick who, when and which tech.",
            steps: [
                HelpStep(symbol: "plus.circle", text: "Tap New job at the bottom of the menu, or the + at the top of Schedule or Jobs."),
                HelpStep(symbol: "text.cursor", text: "Say what is wrong, for example \"Water heater leaking\"."),
                HelpStep(symbol: "person.crop.circle", text: "Pick the customer, a time and a tech."),
                HelpStep(symbol: "tray", text: "Save the job. With no time set, it waits under Unscheduled until it is booked."),
            ],
            keywords: ["create", "add job", "schedule a job", "unscheduled", "assign"],
            related: ["schedule-day", "customer-add"]),
        HelpArticle(
            id: "estimate-build", category: "Estimates and invoices", title: "Build an estimate",
            summary: "Add price book items, offer options and get it signed on your phone.",
            steps: [
                HelpStep(symbol: "doc.badge.plus", text: "Tap + and choose New estimate, or start one from the job's Money tab."),
                HelpStep(symbol: "book.closed", text: "Add items from the price book. Minus and plus on a line change its quantity."),
                HelpStep(symbol: "square.on.square", text: "Tap Add option to give the customer a choice."),
                HelpStep(symbol: "signature", text: "Tap Show to customer and hand over the phone. They choose, read it and sign to approve."),
            ],
            note: "A reason added to a discount shows on the customer's estimate.",
            keywords: ["quote", "proposal", "option", "approve", "sign", "discount", "price book"],
            related: ["invoice-issue", "job-start-finish"]),
        HelpArticle(
            id: "invoice-issue", category: "Estimates and invoices", title: "How do I send an invoice?",
            summary: "Create it on the job, check the lines, then issue it.",
            steps: [
                HelpStep(symbol: "doc.text", text: "On the job, tap Create invoice. Its draft opens straight away."),
                HelpStep(symbol: "list.bullet", text: "Check the lines. Add price book items or change quantities."),
                HelpStep(symbol: "paperplane", text: "Tap Issue invoice when it is right. A draft is not final until you issue it."),
                HelpStep(symbol: "magnifyingglass", text: "Find it later under Invoices by the customer's name or the invoice number."),
            ],
            note: "When payment is due on the spot, the button reads Issue and collect payment and opens payment next.",
            keywords: ["bill", "billing", "issue", "draft", "create invoice"],
            related: ["payment-collect", "payment-link"]),
        HelpArticle(
            id: "payment-collect", category: "Getting paid", title: "Collect payment on site",
            summary: "Tap to Pay, a code to scan, check, cash or a bank transfer.",
            steps: [
                HelpStep(symbol: "creditcard", text: "Open the invoice and tap Collect payment."),
                HelpStep(symbol: "dollarsign.circle", text: "Check the amount."),
                HelpStep(symbol: "wave.3.right", text: "Choose how: Tap to Pay on iPhone when your business has it set up, Show a code to scan, Check, Cash, or Bank transfer or other."),
                HelpStep(symbol: "checkmark.circle", text: "Finish on the phone. The invoice shows the new balance."),
            ],
            note: "Cards, payment links and Tap to Pay need signal. Cash and checks can be recorded with no signal and send when you are back online.",
            keywords: ["pay", "paid", "card", "tap to pay", "cash", "check", "cheque", "ach", "charge", "money"],
            related: ["payment-link", "offline"]),
        HelpArticle(
            id: "payment-link", category: "Getting paid", title: "Let a customer scan to pay",
            summary: "Show a code on your phone, or share the payment link.",
            steps: [
                HelpStep(symbol: "creditcard", text: "On the invoice, tap Collect payment and choose Show a code to scan."),
                HelpStep(symbol: "qrcode", text: "The customer scans the code with their phone camera and pays by card."),
                HelpStep(symbol: "square.and.arrow.up", text: "Or tap Text the link instead to share the link, or Copy link."),
            ],
            note: "A payment link expires. If it has, create a new one from the same screen.",
            keywords: ["qr", "qr code", "link", "pay link", "text a link", "checkout"],
            related: ["payment-collect"]),
        HelpArticle(
            id: "customer-add", category: "Customers", title: "Add or change a customer",
            summary: "New customers, edits, and where they heard about you.",
            steps: [
                HelpStep(symbol: "person.badge.plus", text: "Tap + and choose New customer."),
                HelpStep(symbol: "text.cursor", text: "Add their name, phone, email and address. Under How they found us, write where they heard about you."),
                HelpStep(symbol: "pencil", text: "To change a customer later, open them and choose Edit from the ••• menu."),
                HelpStep(symbol: "archivebox", text: "Archive a customer you no longer work with, with a reason. Archived customers can be restored."),
            ],
            note: "Marketing counts the How they found us answers to show where your customers come from.",
            keywords: ["client", "contact", "edit", "archive", "referral", "lead source", "how they found us"],
            related: ["customer-import", "job-new"]),
        HelpArticle(
            id: "customer-import", category: "Customers", title: "Bring customers in from a spreadsheet",
            summary: "Import a CSV file from your old software.",
            steps: [
                HelpStep(symbol: "gearshape", text: "Open Settings and choose Import customers."),
                HelpStep(symbol: "doc", text: "Choose a CSV file of up to 5 MB."),
                HelpStep(symbol: "tablecells", text: "Check that the columns line up, then import."),
            ],
            note: "Import customers shows only for people who may add and edit customers.",
            keywords: ["csv", "excel", "spreadsheet", "migrate", "upload", "import"],
            related: ["customer-add"]),
        HelpArticle(
            id: "messages", category: "Messages", title: "What is in Messages",
            summary: "Calls, texts, email and job notices in one place.",
            steps: [
                HelpStep(symbol: "bubble.left", text: "Messages lists calls to your business, texts, email and job notices."),
                HelpStep(symbol: "phone", text: "Open a call to play its recording, read the summary and link it to a job."),
                HelpStep(symbol: "message", text: "Text on a job or a customer opens their conversation in Messages."),
                HelpStep(symbol: "square.and.pencil", text: "What you write there is saved as a draft on this phone."),
            ],
            note: "Drafts and queued messages in Messages are not sent from the app.",
            keywords: ["inbox", "sms", "text", "call", "voicemail", "email", "notice", "draft"],
            related: ["text-not-received", "on-this-phone"]),
        HelpArticle(
            id: "text-not-received", category: "Messages", title: "Why didn't my customer get a text?",
            summary: "What the app sends, what it keeps as a draft, and when.",
            steps: [
                HelpStep(symbol: "square.and.pencil", text: "A text written in Messages is a draft on this phone. It is not sent from the app."),
                HelpStep(symbol: "star.bubble", text: "A review request goes out only when Review requests is on, a review link is saved and the customer agreed to texts."),
                HelpStep(symbol: "clock", text: "It is sent once, after an invoice is paid in full, between 8 AM and 8 PM the customer's time, and never twice in 90 days."),
                HelpStep(symbol: "clock.badge.exclamationmark", text: "Running late, in a job's ••• menu, texts the customer a new time from your own phone."),
            ],
            note: "Check the phone number on the customer's page too.",
            keywords: ["sms", "message", "not sent", "didn't send", "review request", "consent", "running late"],
            related: ["messages", "reviews"]),
        HelpArticle(
            id: "offline", category: "On this phone", title: "Work with no signal",
            summary: "Keep working; what you save waits on this phone and sends later.",
            steps: [
                HelpStep(symbol: "icloud.slash", text: "Keep working. Today's jobs, customers, estimates and invoices still open."),
                HelpStep(symbol: "iphone", text: "Changes, photos and signatures are saved on this phone. A line at the top of the app counts what is waiting."),
                HelpStep(symbol: "icloud.and.arrow.up", text: "When signal returns, they send on their own."),
                HelpStep(symbol: "tray.full", text: "Tap that line to review saved work. Send now sends it; Retry or Dismiss deals with anything that could not be saved."),
            ],
            note: "Cards, payment links and Tap to Pay need signal.",
            keywords: ["offline", "wifi", "no service", "sync", "queued", "saved work", "basement", "airplane"],
            related: ["on-this-phone", "payment-collect"]),
        HelpArticle(
            id: "on-this-phone", category: "On this phone", title: "What \"On this phone\" means",
            summary: "Some records are kept only on this phone and are not shared.",
            steps: [
                HelpStep(symbol: "iphone", text: "Some places keep their records only on this phone: Fleet, Training, Marketing's campaign notes and message drafts."),
                HelpStep(symbol: "person.2.slash", text: "The office and your other devices do not see them."),
                HelpStep(symbol: "arrow.clockwise", text: "They stay through restarts and updates. Deleting the app removes them."),
                HelpStep(symbol: "building.2", text: "Each business you sign in to has its own, so switching business never mixes them."),
            ],
            keywords: ["local", "device", "not synced", "saved on this phone", "backup", "lost"],
            related: ["offline"]),
        HelpArticle(
            id: "menu-edit", category: "Menu and settings", title: "Change your menu and start screen",
            summary: "Pin places, hide ones you don't use, and pick where the app opens.",
            steps: [
                HelpStep(symbol: "slider.horizontal.3", text: "Open Settings and choose Menu and start screen."),
                HelpStep(symbol: "rectangle.on.rectangle", text: "Under Open the app to, pick the place the app opens on."),
                HelpStep(symbol: "star", text: "Under Pin to the top, add the places you use most. Drag pinned places to reorder them."),
                HelpStep(symbol: "eye.slash", text: "Under Show in menu, turn a place off to hide it. Nothing is removed."),
            ],
            note: "Reset to the standard layout puts everything back.",
            keywords: ["drawer", "sidebar", "reorder", "pin", "hide", "customize", "start screen", "home screen"],
            related: ["settings"]),
        HelpArticle(
            id: "settings", category: "Menu and settings", title: "Find your way around Settings",
            summary: "Account, notifications, appearance and what changed.",
            steps: [
                HelpStep(symbol: "gearshape", text: "Open the menu, tap the gear at the bottom and choose Settings."),
                HelpStep(symbol: "person.crop.circle", text: "Your name at the top opens Account and data: change your name or password, and see Privacy and permissions."),
                HelpStep(symbol: "bell", text: "Notifications turns notifications on for this phone."),
                HelpStep(symbol: "circle.lefthalf.filled", text: "Appearance is Light, Dark or Match device. It changes right away, on this phone only."),
                HelpStep(symbol: "sparkles", text: "What's new lists what changed in each update."),
            ],
            keywords: ["password", "dark mode", "theme", "sign out", "log out", "notifications", "privacy", "account"],
            related: ["menu-edit"]),
        HelpArticle(
            id: "team-add", category: "Menu and settings", title: "How do I add a technician?",
            summary: "Invite them by email from Team.",
            steps: [
                HelpStep(symbol: "person.2", text: "Open Team from the menu."),
                HelpStep(symbol: "person.badge.plus", text: "Tap Invite to team, the person with a plus at the top."),
                HelpStep(symbol: "envelope", text: "Enter their email and choose their role, then send the invite."),
                HelpStep(symbol: "checkmark.circle", text: "They join from the invite. Until then they show under Invited."),
            ],
            note: "Only people who may manage the team see the invite button.",
            keywords: ["tech", "employee", "staff", "invite", "user", "member", "role", "hire"],
            related: ["settings"]),
        HelpArticle(
            id: "reviews", category: "Customers", title: "Ask customers for a review",
            summary: "Save your review link once; show it as a code any time.",
            steps: [
                HelpStep(symbol: "star.bubble", text: "Open Settings and choose Review requests."),
                HelpStep(symbol: "link", text: "Paste your review link: one https link of up to 100 characters."),
                HelpStep(symbol: "switch.2", text: "Turn on Ask for reviews."),
                HelpStep(symbol: "qrcode", text: "In Marketing, show the link as a code a customer can scan, or copy and share it."),
            ],
            note: "Review requests shows for people who may change company settings.",
            keywords: ["google", "rating", "stars", "feedback", "review link", "qr"],
            related: ["text-not-received", "customer-add"]),
        HelpArticle(
            id: "search", category: "Menu and settings", title: "Find a job, customer or invoice",
            summary: "Search from the top of the menu.",
            steps: [
                HelpStep(symbol: "line.3.horizontal", text: "Open the menu. Search sits at the top."),
                HelpStep(symbol: "magnifyingglass", text: "Type a street, a name, a phone number or a job or invoice number."),
                HelpStep(symbol: "clock.arrow.circlepath", text: "What you opened lately shows before you type."),
            ],
            keywords: ["find", "look up", "lookup", "address", "phone number"],
            related: ["schedule-day"]),
    ]
}

/// Search over the built-in articles. Every typed word must appear somewhere in the article;
/// a word in the title counts most, then a keyword, then the rest.
enum HelpSearch {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") }).map(String.init)
    }

    /// 0 when the article does not match every word.
    static func score(_ article: HelpArticle, words: [String]) -> Int {
        guard !words.isEmpty else { return 0 }
        let title = fold(article.title)
        let keywords = fold(article.keywords.joined(separator: " "))
        let body = fold(([article.summary, article.category, article.note ?? ""] + article.steps.map(\.text)).joined(separator: " "))
        var total = 0
        for word in words {
            if title.contains(word) { total += 3 }
            else if keywords.contains(word) { total += 2 }
            else if body.contains(word) { total += 1 }
            else { return 0 }
        }
        return total
    }

    /// Best match first; equal matches keep the catalogue's order.
    static func results(_ query: String, in articles: [HelpArticle] = HelpCatalog.articles) -> [HelpArticle] {
        let typed = words(query)
        guard !typed.isEmpty else { return [] }
        var scored: [(index: Int, article: HelpArticle, score: Int)] = []
        for (index, article) in articles.enumerated() {
            let value = score(article, words: typed)
            if value > 0 { scored.append((index: index, article: article, score: value)) }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.index < rhs.index
        }
        return scored.map { $0.article }
    }
}

/// Paper 98 "Take a tour": the three it names, as cards over the Help page. They explain the
/// steps in words; they do not point at controls on other screens.
enum HelpTours {
    static let all: [GuidedTour] = [firstJob, gettingPaid, estimate]

    static let firstJob = GuidedTour(name: "Your first job", steps: [
        GuidedTourStep(id: "first-job-schedule", target: nil, title: "Start on Schedule",
                       message: "Today lists your stops in order. Week shows what's coming. Map shows every stop."),
        GuidedTourStep(id: "first-job-open", target: nil, title: "Open the job",
                       message: "The button at the bottom is always the next step: On my way, I've arrived, then Start work."),
        GuidedTourStep(id: "first-job-work", target: nil, title: "Record the work",
                       message: "Add photos and notes as you go. Tag photos Before or After."),
        GuidedTourStep(id: "first-job-wrap", target: nil, title: "Wrap up",
                       message: "Wrap up lists what is left: photos, note, approval, signature and payment. Then tap Complete job."),
    ])

    static let gettingPaid = GuidedTour(name: "Getting paid on site", steps: [
        GuidedTourStep(id: "paid-invoice", target: nil, title: "Start from the invoice",
                       message: "On the job, tap Create invoice, check the lines and tap Issue invoice."),
        GuidedTourStep(id: "paid-collect", target: nil, title: "Tap Collect payment",
                       message: "Check the amount, then choose Tap to Pay on iPhone, a code to scan, Check, Cash or a bank transfer."),
        GuidedTourStep(id: "paid-offline", target: nil, title: "No signal?",
                       message: "Cash and checks can be recorded offline and send later. Cards and payment links need signal."),
    ])

    static let estimate = GuidedTour(name: "Building an estimate", steps: [
        GuidedTourStep(id: "estimate-new", target: nil, title: "Start a new estimate",
                       message: "Tap + and choose New estimate, or start one from the job's Money tab."),
        GuidedTourStep(id: "estimate-items", target: nil, title: "Add what you will do",
                       message: "Add items from the price book. Add option gives the customer a choice."),
        GuidedTourStep(id: "estimate-show", target: nil, title: "Show to customer",
                       message: "Hand over the phone. They choose an option, read it and sign to approve."),
    ])

    /// Paper 98's row titles.
    static func title(_ tour: GuidedTour) -> String {
        switch tour.name {
        case firstJob.name: "Your first job, start to finish"
        default: tour.name
        }
    }
}
