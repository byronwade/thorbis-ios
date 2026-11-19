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
            id: "2026-11-19-cleaner-menu",
            date: "2026-11-19",
            highlights: [
                .init(symbol: "person.crop.circle", title: "Tidier menu",
                      detail: "Your name is one row that opens Settings, Notifications joins the list, and long names no longer cut off."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-19-instant-documents",
            date: "2026-11-19",
            highlights: [
                .init(symbol: "bolt", title: "Estimates and invoices open at once",
                      detail: "They show the copy saved on your phone first, then update. Actions wait for the live copy."),
                .init(symbol: "dock.rectangle", title: "New bottom bar",
                      detail: "Search on the left, your places and the menu in the middle, your settings on the right."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-menu-motion",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "sidebar.left", title: "Smoother menu",
                      detail: "The menu opens faster with a soft landing, closes quicker, and follows the speed of your swipe."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-instant-job",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "bolt", title: "Jobs open right away",
                      detail: "A job shows at once from what your phone already has, then updates when the server answers."),
                .init(symbol: "arrow.triangle.branch", title: "Job details load together",
                      detail: "Contacts, notes, photos, estimates and invoices are fetched at the same time instead of one by one."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-simpler-more",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "ellipsis.circle", title: "More shows only what's not in the bar",
                      detail: "The More menu no longer repeats Schedule, Jobs and the other tabs. It lists everything else, once."),
                .init(symbol: "list.bullet", title: "Every place is in the menu",
                      detail: "Places that were tucked inside Settings, like Estimates and Invoices, are now under Everything else."),
                .init(symbol: "gearshape", title: "Notifications and Settings have words",
                      detail: "The bell and gear at the foot of the menu are now labeled buttons."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-bottom-bar",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "dock.rectangle", title: "Bottom bar on iPhone",
                      detail: "Your main places sit in a labelled bar at the bottom. More opens the full menu. Sidebar is still in Settings."),
                .init(symbol: "rectangle.split.3x1", title: "Cleaner tabs",
                      detail: "Today, Week and other tabs sit on a quiet track with the chosen one raised in white."),
                .init(symbol: "bubble.left.and.bubble.right", title: "Simpler Messages",
                      detail: "One row of filters: All, Unread, Calls, Texts, Email, Drafts. Folders moved to the menu beside +."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-one-signature",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "signature", title: "One signature, several estimates",
                      detail: "In Customer view, a customer can pick the estimates they want and approve them all with one signature."),
                .init(symbol: "checkmark.shield", title: "Each approval is confirmed",
                      detail: "Estimates are approved one at a time. If one can't be confirmed, the run stops and says which need checking."),
                .init(symbol: "keyboard", title: "Done stays above the keyboard",
                      detail: "In the price book, Done could sit behind the keyboard after editing a quantity. It now stays in reach."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-menu-crash",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "bolt.shield", title: "Fixed a crash opening screens",
                      detail: "Opening a conversation or another screen with a menu in its top bar could close the app. It no longer does."),
                .init(symbol: "textformat.size", title: "Largest text sizes read cleanly",
                      detail: "On Schedule, invoices and Messages, icons no longer sit on text and names are no longer cut or split."),
                .init(symbol: "hand.tap", title: "Stacked choices are easier to tap",
                      detail: "Choices stacked at large text no longer overlap, so a tap between two always picks the one you meant."),
                .init(symbol: "number", title: "Menu counts stay short",
                      detail: "Counts in the menu read 1,204, and the unread badge stops at 999+."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-real-data-fixes",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "calendar", title: "Schedule stays about the day",
                      detail: "Schedule shows the three oldest waiting jobs and a See all row. The full queue has its own searchable page."),
                .init(symbol: "lock.iphone", title: "Lock Screen card fits",
                      detail: "The job card on the Lock Screen no longer cuts off its top or its button, and ends after 16 hours."),
                .init(symbol: "clock", title: "Long times read in days",
                      detail: "A job left open for days reads 19d 15h on timers and cards, not hundreds of hours."),
                .init(symbol: "textformat", title: "Long names stay in place",
                      detail: "Long job titles and customer names keep to their row and stay between the buttons in the top bar."),
                .init(symbol: "list.bullet", title: "Big lists show a few first",
                      detail: "Needs attention shows five per group with See all. Counts read 3,000, not 3000."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-one-look",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "rectangle.3.group", title: "One look for every screen",
                      detail: "Page titles, section labels, buttons, chips and fields now share one size and spacing on every screen."),
                .init(symbol: "exclamationmark.bubble", title: "Confirms and messages match",
                      detail: "Every confirm is the same centred card. Error banners, empty lists and loading lines share one design."),
                .init(symbol: "dock.rectangle", title: "Bottom bars and sheets line up",
                      detail: "Pinned buttons sit at the same height everywhere, and sheets share one Cancel, title and action bar."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-simpler-menu",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "sidebar.left", title: "A shorter menu",
                      detail: "The menu lists only your main places. Everything else opens from Search, Money, Team or Settings."),
                .init(symbol: "gearshape", title: "Gear opens Settings",
                      detail: "The gear goes straight to Settings. Tap the business name to switch business or add one."),
                .init(symbol: "ellipsis.circle", title: "Shorter job More menu",
                      detail: "More has eight rows. Scheduling is on the clock chip, assigning on the person chip, sharing on Share."),
                .init(symbol: "dollarsign.circle", title: "Estimates and invoices in Money",
                      detail: "Money links to the Estimates and Invoices lists. Show estimates is on the job's Money section."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-present-estimates",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "doc.on.doc", title: "Present all of a job's estimates",
                      detail: "Show customer on an estimate opens every estimate on its job, starting with the one you tapped."),
                .init(symbol: "person.crop.rectangle", title: "Cleaner customer view",
                      detail: "The customer's page follows the new design, with one Hand back to technician button at the foot."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-opening-workspace-fix",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "hourglass", title: "No more stuck on opening",
                      detail: "The app could freeze on Opening your workspace for a company with many jobs. The Schedule board is fixed."),
                .init(symbol: "bolt", title: "Faster with a large company",
                      detail: "Schedule, Jobs, Customers and Search open in seconds with thousands of jobs and customers."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-crash-fixes",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "person.2", title: "Customer page crash fixed",
                      detail: "Opening a customer could close the app when one of their jobs was listed twice. Fixed."),
                .init(symbol: "mic", title: "First voice note crash fixed",
                      detail: "Answering the speech permission prompt the first time you tap a microphone no longer closes the app."),
                .init(symbol: "list.bullet", title: "Long lists open faster",
                      detail: "Customers and Jobs build only the rows on screen, so large books no longer stall or run out of memory."),
                .init(symbol: "briefcase", title: "Job page stays steady",
                      detail: "A job page returns to the top when its visit steps appear or go, instead of risking a freeze."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-menu-and-sign-out-fixes",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "hand.tap", title: "Scrolling a menu no longer picks a row",
                      detail: "Scrolling a long menu, like a job's More, with your finger on a row no longer chooses that row."),
                .init(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out fits large text",
                      detail: "The sign-out sheet scrolls at the largest text sizes, so Cancel is always within reach."),
                .init(symbol: "keyboard", title: "Line editor clears the keyboard",
                      detail: "On an invoice, the open line moves above the keyboard so Done and Remove are never covered."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-team-and-company",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "person.badge.key", title: "Roles and Ownership pages",
                      detail: "Team's menu opens Roles and Ownership. Role editors moved from the menu to the Roles page."),
                .init(symbol: "envelope", title: "Invites redrawn",
                      detail: "Invite member is a full page with email and role. A pending invite opens its own page."),
                .init(symbol: "person.crop.rectangle", title: "Team member page",
                      detail: "A member shows this week's jobs. Permissions, Make owner and Remove are in the page's menu."),
                .init(symbol: "building.2", title: "Company profile in rows",
                      detail: "Company profile is a page of rows. Tap a row to edit that field. Hours, tax and plan are rows too."),
                .init(symbol: "bell", title: "iPad bell opens Notifications",
                      detail: "The bell in the iPad sidebar opens Notifications instead of Messages."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-people-sheets",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "square.and.pencil", title: "New message finds customers",
                      detail: "Type a name to pick a customer or a saved reply. It opens the conversation; nothing sends by itself."),
                .init(symbol: "archivebox", title: "Archived customers",
                      detail: "A customer's details page links to recently archived customers, where you can find and restore them."),
                .init(symbol: "switch.2", title: "Texts consent is a switch",
                      detail: "Job texts is a switch like Emails. It still asks before recording, and shows the day it was recorded."),
                .init(symbol: "tray.and.arrow.down", title: "Import shows what the file has",
                      detail: "Import customers lists only the columns your file fills; the rest sit behind one row."),
                .init(symbol: "truck.box", title: "Vehicle details read cleaner",
                      detail: "Mileage, registration and next service print as 84,210 mi and Jun 30, 2027, with a warning when due."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-job-sheets",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "plus.circle", title: "Add to job",
                      detail: "A job's More menu has Add to job: estimate, invoice, photo or video, note and contact in one sheet."),
                .init(symbol: "clock", title: "Time on a job",
                      detail: "More opens Time and profit: drive time, time on site and time by technician. Profit is not shown yet."),
                .init(symbol: "person.crop.circle", title: "Job contact page",
                      detail: "A job contact opens on Call, Text and Email with the contact's number and email below."),
                .init(symbol: "mic", title: "Voice notes and documents",
                      detail: "Record a voice note with a live transcript. Documents has a + for a camera scan, photos or files."),
                .init(symbol: "qrcode", title: "Scan to pay and revisions",
                      detail: "Scan to pay shows a larger amount and code. Estimate revisions name what changed in the newest one."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-job-money-guards",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "creditcard", title: "Collect payment stays on Money",
                      detail: "Collect payment opens only while you are still on the job's Money section, never over another one."),
                .init(symbol: "lock.shield", title: "Job invoices close on sign-in change",
                      detail: "An invoice opened from a job closes if your sign-in or permissions change while it is open."),
                .init(symbol: "trash", title: "Remove is harder to hit by mistake",
                      detail: "On the invoice line editor, the gap between Done and Remove is back to its full size."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-paper-office",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "square.grid.2x2", title: "Dashboard and Money redrawn",
                      detail: "Dashboards, Money and Reports follow the new design, with search at the top and only real figures."),
                .init(symbol: "person.2", title: "Customers and Messages redrawn",
                      detail: "A customer is one page with Jobs, Billing, Media and Activity. Messages is one list with filters."),
                .init(symbol: "doc.text", title: "Estimates, invoices and payments",
                      detail: "New estimate ends in Present to customer. Edit invoice and Collect payment follow the new design."),
                .init(symbol: "gearshape", title: "Settings split in two",
                      detail: "Settings is about you. Company profile, payments, reviews and rules moved to Business settings."),
                .init(symbol: "list.bullet.rectangle", title: "Setup, step by step",
                      detail: "Guided setup has a back button on every step and asks only what each step needs."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-18-paper-field",
            date: "2026-11-18",
            highlights: [
                .init(symbol: "calendar", title: "Schedule redrawn",
                      detail: "One Next up card with Navigate, call and text, then the rest of the day as a short list."),
                .init(symbol: "briefcase", title: "Field mode on a job",
                      detail: "Today's job opens on its step: Driving, Arrived, Working, Wrap up, Paid. More opens full details."),
                .init(symbol: "sidebar.left", title: "A new menu",
                      detail: "The menu floats over the screen as a panel, with new icons and an unread count on Messages."),
                .init(symbol: "clock", title: "Times read 10:30 AM",
                      detail: "Times across the app use AM and PM in capitals, and today's visits read Today, 2:30 PM."),
                .init(symbol: "bell", title: "Notifications has its own place",
                      detail: "The bell opens Notifications as its own screen, and Properties opens from the menu too."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-17-saved-views",
            date: "2026-11-17",
            highlights: [
                .init(symbol: "bookmark", title: "Saved views on Jobs",
                      detail: "Your saved views from the web show under the Jobs search. Tap one to apply it, or save the filters you set."),
                .init(symbol: "calendar.badge.clock", title: "Waiting for a slot",
                      detail: "Follow-ups the field asked the office to book sit on top of Unscheduled, ready to schedule."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-17-customer-and-settings",
            date: "2026-11-17",
            highlights: [
                .init(symbol: "phone", title: "Texts and calls on a customer",
                      detail: "A customer's page lists their calls and this phone's drafts to them, newest first."),
                .init(symbol: "note.text", title: "Customer notes",
                      detail: "Keep notes on a customer. They stay on this phone; property notes from the office show under them."),
                .init(symbol: "bell", title: "Notifications",
                      detail: "The bell in the menu opens your job notices: what was booked, changed or assigned, and what is unread."),
                .init(symbol: "checklist", title: "Checklists in Business settings",
                      detail: "Owners edit what techs confirm before finishing a job, and see what customers see in one place."),
                .init(symbol: "signature", title: "Saved signature",
                      detail: "Settings keeps your own signature on this phone, ready for when the app needs it."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-17-office-places",
            date: "2026-11-17",
            highlights: [
                .init(symbol: "line.3.horizontal.decrease", title: "Pipeline",
                      detail: "Office and owners keep leads by stage, call or text them, and mark them won or lost. Saved on this phone."),
                .init(symbol: "cart", title: "Vendors and purchase orders",
                      detail: "Keep vendors, write numbered purchase orders, check items in, and share an order as text or PDF."),
                .init(symbol: "megaphone", title: "Marketing",
                      detail: "Owners see where customers came from, show the review link as a code to scan, and keep campaign notes."),
                .init(symbol: "questionmark.circle", title: "Help and support",
                      detail: "Settings has Help: search short articles about this app and take a guided tour."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-17-field-places",
            date: "2026-11-17",
            highlights: [
                .init(symbol: "clock", title: "Time clock",
                      detail: "Clock in and out, take breaks, fix a missed clock-out and see your week. Hours stay on this phone."),
                .init(symbol: "receipt", title: "Receipts",
                      detail: "Photograph a receipt and its merchant, date and total are read for you. Share a month as a CSV."),
                .init(symbol: "cube", title: "Truck stock",
                      detail: "Count what is on the truck, set a minimum, and share a restock list of everything running low."),
                .init(symbol: "graduationcap", title: "Training",
                      detail: "Keep your licences with their expiry dates and card photos, and the courses you are taking."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-17-sheet-titles",
            date: "2026-11-17",
            highlights: [
                .init(symbol: "textformat.size", title: "Sheet titles at large text",
                      detail: "On New customer, Add equipment and Add property, Cancel and Save stay on one line at the largest text sizes."),
                .init(symbol: "building.2", title: "Business settings in the owner's menu",
                      detail: "Owners open Business settings straight from the menu, under Business. It can also be the start screen."),
                .init(symbol: "person.badge.plus", title: "Customer service and accountant invites",
                      detail: "An invite for Customer service no longer fails, and Accountant is now a role you can invite."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-17-customer-pages-open",
            date: "2026-11-17",
            highlights: [
                .init(symbol: "hand.tap", title: "Customer pages open what you tap",
                      detail: "On a customer's Money and Jobs pages, estimates, invoices, photos, documents and jobs open again."),
                .init(symbol: "iphone", title: "Show customer, in one place",
                      detail: "The job keeps one Show customer row in its details in every state, and the Money tab is called Money again."),
                .init(symbol: "envelope", title: "Email sends from the composer",
                      detail: "Send is the main button again; Send with Mail and Save draft sit under it."),
                .init(symbol: "signature", title: "Signature box for VoiceOver",
                      detail: "The box customers sign in is announced, with whether a signature has been entered."),
                .init(symbol: "list.bullet", title: "See all jobs works",
                      detail: "On a customer with several open jobs, See all jobs opens the Jobs page."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-office-pages",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "building.2", title: "Business settings in one place",
                      detail: "Company, payments, operations and team settings are listed together on one page."),
                .init(symbol: "phone.bubble", title: "A fuller call page",
                      detail: "Read the whole transcript, play the recording faster, and link the call to a job from its menu."),
                .init(symbol: "icloud.and.arrow.up", title: "Send saved work now",
                      detail: "Saved on this phone lists what is waiting, with Send now and Keep working at the bottom."),
                .init(symbol: "chart.bar", title: "Dashboard and Money you can fold",
                      detail: "Tap a section's label to fold it away; the dashboard also shows what was collected today."),
                .init(symbol: "magnifyingglass", title: "Price book search up top",
                      detail: "Search and switch between kinds of item at the top of the price book."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-estimate-versions",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "clock.arrow.circlepath", title: "Estimate versions",
                      detail: "See every version you sent, what changed in each, and restore an older one as a new draft."),
                .init(symbol: "doc.text.viewfinder", title: "Scan parts into an estimate",
                      detail: "Scan or paste a parts list when you build a new estimate, the same as on invoices."),
                .init(symbol: "tag", title: "Say why you gave a discount",
                      detail: "Add a reason to a discount and your customer sees it on the estimate."),
                .init(symbol: "crop", title: "Crop your logo",
                      detail: "Move and zoom your logo before it goes on invoices and texts."),
                .init(symbol: "hand.raised", title: "Why we ask for access",
                      detail: "A short page explains each permission before your phone asks for it."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-schedule-and-booking",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "line.3.horizontal.decrease", title: "Filter jobs your way",
                      detail: "Filter Jobs by tech, unassigned, status or a date range, and sort by time, update or name."),
                .init(symbol: "square.and.pencil", title: "A quicker New job",
                      detail: "Start with what's wrong, then pick the customer, time and tech from chips under it."),
                .init(symbol: "checklist", title: "Setup steps on an empty schedule",
                      detail: "Until setup is finished, an empty schedule shows what is left and takes you there."),
                .init(symbol: "map", title: "Call or book from the map",
                      detail: "The map's stop card can call the customer or book another job at that address."),
                .init(symbol: "person.2", title: "A suggested tech",
                      detail: "Assign shows who has the fewest jobs that day first, and how many each tech has."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-job-in-the-field",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "timer", title: "An on-site timer",
                      detail: "While you work, the job shows time on site with Pause, and tiles for photo, voice note and parts."),
                .init(symbol: "ellipsis.circle", title: "A clearer job menu",
                      detail: "The job menu opens from the bottom, and you can cancel a job or jump to its details from it."),
                .init(symbol: "flag.checkered", title: "When each step happened",
                      detail: "Job status shows the time you were dispatched, started driving and arrived."),
                .init(symbol: "pencil.tip", title: "Better photo markup",
                      detail: "Draw with a pen or highlighter in five colours, erase, and undo or redo."),
                .init(symbol: "rectangle.split.2x1", title: "Share before and after",
                      detail: "Send a before-and-after pair as one picture, and add captions to photos."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-customer-records",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "archivebox", title: "Archive customers",
                      detail: "Archive a customer with a reason, see archived customers on their own page, and restore them."),
                .init(symbol: "person.badge.plus", title: "Save and book in one step",
                      detail: "Save a new customer and go straight to booking their job; note how they found you."),
                .init(symbol: "wrench.and.screwdriver", title: "Pages for units and trucks",
                      detail: "Each piece of equipment and each truck opens its own page; start a job from a unit."),
                .init(symbol: "house", title: "More on a property",
                      detail: "Get directions, edit access notes, call or text contacts and start a job from a property."),
                .init(symbol: "list.bullet.below.rectangle", title: "A customer timeline",
                      detail: "A customer's activity is a timeline you can filter to visits or payments."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-field-and-ipad-paper",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "arrow.up.left.and.arrow.down.right", title: "Write descriptions full screen",
                      detail: "Open a line's description in a full editor and preview how your customer will read it."),
                .init(symbol: "car", title: "A clearer next stop",
                      detail: "Today's card shows the drive and access note; after you're paid, On my way to the next stop is one tap."),
                .init(symbol: "ipad.landscape", title: "Board and Money on iPad",
                      detail: "The Board and Money pages use the full width on iPad, and Schedule opens side by side."),
                .init(symbol: "lock.iphone", title: "New widgets and Lock Screen",
                      detail: "The Lock Screen shows the job, a timer and one button; widgets list today's jobs by time."),
                .init(symbol: "person.text.rectangle", title: "A friendlier customer view",
                      detail: "Customers see a greeting, their estimates and invoices, and their own contact details."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-join-a-team",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "person.badge.plus", title: "Join a team from an invite",
                      detail: "Open or paste your invite link to join; switch between companies from Join another workspace."),
                .init(symbol: "sparkles", title: "A short intro for new phones",
                      detail: "Three quick pages show what Thorbis does before you log in for the first time."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-account-pages",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "person.crop.circle", title: "Edit your name and password",
                      detail: "From Settings, Account and data: change your name or password without leaving the app."),
                .init(symbol: "hand.raised", title: "See what the app can use",
                      detail: "Privacy and permissions lists camera, location, microphone and notification access."),
                .init(symbol: "bell", title: "Your own notifications page",
                      detail: "Turn notifications on and choose your morning summary from Settings, Notifications."),
                .init(symbol: "xmark.circle", title: "Cancel a maintenance plan clearly",
                      detail: "Cancelling a plan opens its own page that says what ends before you confirm."),
                .init(symbol: "barcode.viewfinder", title: "Scan or paste materials",
                      detail: "On an invoice, scan part codes or paste a parts list and add the price book matches."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-estimates-invoices-paper",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "doc.text", title: "Estimate and invoice pages, redone",
                      detail: "Each shows its number, status and progress up top, then the lines and an Edit button."),
                .init(symbol: "plus.forwardslash.minus", title: "Change quantities in place",
                      detail: "Line items have a minus and plus right in the row while you build an estimate or invoice."),
                .init(symbol: "signature", title: "A cleaner signature pad",
                      detail: "Customers sign under their name, with Clear beside the pad."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-setup-paper",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "person.badge.key", title: "A fresh log in and sign up",
                      detail: "Logging in, signing up and resetting your password use the new look, with clearer steps."),
                .init(symbol: "checklist", title: "Business setup, step by step",
                      detail: "Each setup step shows where you are, and Business settings groups company, payments and team."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-settings-team-paper",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "gearshape", title: "Settings in clear cards",
                      detail: "Account, workspace, notifications and appearance each have their own card, and Appearance has its own page."),
                .init(symbol: "person.2", title: "Team and permissions, tidied",
                      detail: "See each person's role, open pending invites, and turn permissions on or off per role."),
                .init(symbol: "wrench.and.screwdriver", title: "Equipment, fleet and properties",
                      detail: "Lists and forms for equipment, vans, properties and maintenance plans now match the rest of the app."),
                .init(symbol: "creditcard", title: "A simpler Collect payment",
                      detail: "Tap to Pay leads, with a code to scan, check, cash or bank transfer underneath."),
                .init(symbol: "checkmark.seal", title: "Wrap up, reschedule and assign",
                      detail: "The close-out checklist, moving a visit and assigning a tech all use the new cards and buttons."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-field-day-paper",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "calendar", title: "A cleaner Schedule and Jobs",
                      detail: "Your next stop leads Schedule, and Jobs groups your work by in progress, scheduled and done."),
                .init(symbol: "briefcase", title: "Job pages in cards",
                      detail: "Each part of a job sits in its own card, with status, time and tech as chips under the title."),
                .init(symbol: "clock.badge.exclamationmark", title: "Running late",
                      detail: "From the job's ••• menu, text the customer a new arrival time from your phone."),
                .init(symbol: "hand.raised", title: "Can't start a job",
                      detail: "Tell the office why you can't start, with a note and photos; it lands on the job."),
                .init(symbol: "bubble.left", title: "Messages and Search, restyled",
                      detail: "Conversations, notices and search results now sit in labelled cards by day."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-dashboard-money-paper",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "square.grid.2x2", title: "A clearer Dashboard",
                      detail: "Revenue this month, active techs, jobs in progress and what needs you, each in its own card."),
                .init(symbol: "banknote", title: "Money at a glance",
                      detail: "Collected, outstanding and overdue sit up top, with aging and who to chase below."),
                .init(symbol: "doc.text", title: "Estimates and invoices by status",
                      detail: "Search and switch between open, approved, unpaid, paid and drafts."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-customers-paper",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "person.2", title: "Customers, A to Z",
                      detail: "The customer list is grouped by letter, and each customer page leads with New job, Call and Text."),
                .init(symbol: "square.stack", title: "Everything for a customer in one card",
                      detail: "Jobs, property, equipment, membership and money each open from one card on the customer page."),
                .init(symbol: "pencil", title: "Edit a customer in one sheet",
                      detail: "Change name, phone, email and addresses from the customer's ••• menu."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-account-and-data",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "person.crop.circle", title: "Account and data in Settings",
                      detail: "See your account, open privacy settings, and ask to delete your account from the app."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-paper-menu",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "sidebar.left", title: "A menu built for your role",
                      detail: "Technicians, office staff and owners each see their main places first, then Tools, Manage or Business."),
                .init(symbol: "magnifyingglass", title: "Search or ask from the menu",
                      detail: "Search sits at the top of the menu, with a + button for anything new."),
                .init(symbol: "bubble.left", title: "Inbox is now Messages",
                      detail: "Home is now Dashboard, and office staff get it too."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-16-paper-colors",
            date: "2026-11-16",
            highlights: [
                .init(symbol: "paintpalette", title: "A brighter, clearer look",
                      detail: "New colours in light and dark, a brighter blue, bolder titles and large screen titles."),
                .init(symbol: "line.3.horizontal", title: "Rows are easier to tell apart",
                      detail: "A thin line now sits between rows inside a card, so long lists are easier to scan."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-14-inbox-draft-actions",
            date: "2026-11-14",
            highlights: [
                .init(symbol: "tray", title: "Keep draft actions clear",
                      detail: "Inbox explains when a text can't open and keeps an email draft open if discard fails."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-14-text-draft-recovery",
            date: "2026-11-14",
            highlights: [
                .init(symbol: "doc.on.doc", title: "Keep text when saving fails",
                      detail: "If a text draft can't be saved on this device, copy your words before closing."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-13-present-estimates",
            date: "2026-11-13",
            highlights: [
                .init(symbol: "iphone", title: "Show estimates sooner",
                      detail: "Open customer view before scrolling through a job’s estimates."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-13-savings-label",
            date: "2026-11-13",
            highlights: [
                .init(symbol: "tag", title: "See savings clearly",
                      detail: "Customer estimates and invoices show price reductions as savings."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-13-customer-email",
            date: "2026-11-13",
            highlights: [
                .init(symbol: "envelope", title: "Write customer emails",
                      detail: "Start an email in your inbox, save a draft, or send with Mail."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-13-find-work",
            date: "2026-11-13",
            highlights: [
                .init(symbol: "sidebar.left", title: "Find work in the menu",
                      detail: "Jobs and documents are easy to find, and tapping a section opens or closes it."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-12-estimate-save-and-menu",
            date: "2026-11-12",
            highlights: [
                .init(symbol: "keyboard", title: "Save stays clear of Done",
                      detail: "When you edit an estimate, Done above the keyboard no longer covers Save."),
                .init(symbol: "iphone.landscape", title: "Landscape settings stay on screen",
                      detail: "Turn the phone sideways and the drawer settings menu still keeps Saved work and Settings in reach."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-12-customer-keyboard-done",
            date: "2026-11-12",
            highlights: [
                .init(symbol: "keyboard", title: "Done puts the keyboard away",
                      detail: "When adding a customer, Done above the keyboard puts it away so you can reach Type."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-12-job-document-shortcuts",
            date: "2026-11-12",
            highlights: [
                .init(symbol: "arrow.up.arrow.down", title: "Move between job documents",
                      detail: "Switch between estimates and invoices while scrolling through a job's documents."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-12-job-and-inbox",
            date: "2026-11-12",
            highlights: [
                .init(symbol: "doc.text", title: "Open job documents faster",
                      detail: "Tap an estimate or invoice on the job overview to open that document."),
                .init(symbol: "clock.arrow.circlepath", title: "Browse past jobs in batches",
                      detail: "Load more past jobs on a customer profile, or show the full history."),
                .init(symbol: "envelope", title: "Keep an email draft",
                      detail: "Save a draft before choosing a recipient and recover your words if saving fails."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-11-customer-handoff",
            date: "2026-11-11",
            highlights: [
                .init(symbol: "person.text.rectangle", title: "Review customer changes",
                      detail: "Review saved customer changes together before trying an interrupted update again."),
                .init(symbol: "creditcard", title: "Return to the right invoice",
                      detail: "After customer review, return to the invoice you opened to collect its payment."),
                .init(symbol: "arrow.clockwise", title: "Know when payment needs a check",
                      detail: "If payment details need a refresh, the customer sees what to do next."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-ipad-schedule-list",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "ipad", title: "iPad Schedule matches Jobs",
                      detail: "On iPad, Schedule's list uses the same tabs and plain rows as the Jobs list beside it."),
            ],
            fixes: 27
        ),
        ReleaseNote(
            id: "2026-11-05-section-counts",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "number", title: "Section counts read the same",
                      detail: "Every list and report shows a section's count the same way, the number beside the label."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-new-estimate-header",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "doc.badge.plus", title: "New estimate like other forms",
                      detail: "A new estimate opens with the same title and close button as the other forms."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-11-05-job-notices-and-tabs",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "bell", title: "See if booking notices went out",
                      detail: "A job lists who was emailed or told in the app about the booking, and whether it was sent."),
                .init(symbol: "rectangle.split.3x1", title: "Job tabs show whole words",
                      detail: "Job sections never cut off as “Overvi…”; at larger text they wrap onto a second line."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-11-05-new-customer-sheet",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "person.badge.plus", title: "New customer like other forms",
                      detail: "Adding a customer opens the same sheet as the other forms: a title, the close button and one Save."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-equipment-sheet",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "wrench.and.screwdriver", title: "Add equipment like other forms",
                      detail: "Adding equipment opens the same sheet as the other forms: a title, the close button and one Save."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-forms-read-the-same",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "list.bullet.rectangle", title: "Forms read the same",
                      detail: "Optional fields are marked the same way in every form, and equipment fields show real examples."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-money-overview-tab",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "chart.bar", title: "Money opens on the overview",
                      detail: "Money's first tab shows what's owed, aging and who to chase; Revenue and the reports follow."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-11-05-one-create-button",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "plus.circle", title: "One New button everywhere",
                      detail: "Jobs, Customers, Estimates and Home use the same dark + as Today, Board and Map."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-11-05-money-overview",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "chart.bar", title: "Money at a glance",
                      detail: "See what's owed, collected and billed, how old unpaid invoices are and who to chase first."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-payments-list",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "creditcard", title: "See every payment",
                      detail: "Home's Money section opens every payment collected, by card, cash or refunded, as on the web."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-property-page",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "house", title: "A page for each property",
                      detail: "Properties open their own page: the codes at the door, jobs at that address and the equipment there."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-record-activity",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "clock.arrow.circlepath", title: "See an invoice's history",
                      detail: "Estimates and invoices list who changed, sent or paid them and when, as on the web."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-agreements-server-book",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "doc.text", title: "Agreements shared with your team",
                      detail: "Agreements now lists every maintenance plan and membership on file, the same list the office sees."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-equipment-server-book",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "wrench.and.screwdriver", title: "Equipment shared with your team",
                      detail: "Equipment now lists every unit on file, by customer and address, the same list the office sees."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-customer-job-emails",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "envelope", title: "Turn off job emails for a customer",
                      detail: "On a customer's details, stop booking, schedule and cancel emails for them, as on the web."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-invoice-discount",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "tag", title: "Discount a draft invoice",
                      detail: "Add a discount and a reason the customer sees from the invoice's menu, as on the web."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-calmer-lists-and-screens",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "list.bullet", title: "Calmer job lists",
                      detail: "Rows drop words they repeat, and titles, times and streets no longer break mid-line."),
                .init(symbol: "tray", title: "Notices line up in the Inbox",
                      detail: "Job notices sit beside calls and texts, with the same age and unread dot."),
                .init(symbol: "bell", title: "Notification rules, grouped",
                      detail: "Each role's email and in-app switches sit together in one panel."),
                .init(symbol: "checkmark.circle", title: "One tap to confirm",
                      detail: "Wrap up shows a single Confirm button on each item you can check off."),
                .init(symbol: "dollarsign.circle", title: "Billing reads like Invoices",
                      detail: "Billing schedules show as plain rows, with the amount over the status."),
            ],
            fixes: 13
        ),
        ReleaseNote(
            id: "2026-11-05-text-opens-inbox",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "message", title: "Text opens the Inbox",
                      detail: "Text on a job or customer opens their conversation in the Inbox, where it saves as a draft."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-inbox-calls-texts-email",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "phone", title: "Calls in the Inbox",
                      detail: "See calls to your business by caller, play the recording and link a call to its job."),
                .init(symbol: "bubble.left", title: "Texts and email in the Inbox (beta)",
                      detail: "Texts save as drafts and emails wait in Sent on this phone; nothing goes out yet."),
                .init(symbol: "tray", title: "Sort your Inbox",
                      detail: "Switch between calls, texts, email and job notices, and archive or star conversations."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-web-sidebar-workspaces",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "sidebar.left", title: "Find your workspaces",
                      detail: "The menu now follows the web: open a workspace to see its pages."),
                .init(symbol: "line.3.horizontal", title: "Keep your menu order",
                      detail: "Your saved order is in Your places, which you can collapse when you don't need it."),
                .init(symbol: "plus", title: "Create from the menu",
                      detail: "Choose a new item at the top of the menu; the New job shortcut is still at the bottom."),
                .init(symbol: "star", title: "Favorite jobs and customers",
                      detail: "Save records on this device and find them in Favorites when you have access."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-job-invoice-draft-review",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "doc.text", title: "Open a new invoice right away",
                      detail: "Create an invoice on a job and review its draft in one step."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-job-invoice-collect",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "creditcard", title: "Collect from the invoice list",
                      detail: "On a job, collect payment directly from the invoice you choose."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-05-web-aligned-menu",
            date: "2026-11-05",
            highlights: [
                .init(symbol: "sidebar.left", title: "Find work more easily",
                      detail: "Jobs, estimates and invoices are together in the menu, like on the web."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-04-job-photos-section",
            date: "2026-11-04",
            highlights: [
                .init(symbol: "photo.on.rectangle", title: "Open job photos directly",
                      detail: "Go straight to a job's photos from its section bar."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-04-job-payment-selection",
            date: "2026-11-04",
            highlights: [
                .init(symbol: "creditcard", title: "Keep the selected invoice",
                      detail: "Collect payment stays with the invoice you chose on the job."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-04-customer-payment-history",
            date: "2026-11-04",
            highlights: [
                .init(symbol: "creditcard", title: "See payments at a glance",
                      detail: "Customers can see short payment histories and refunds without an extra tap."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-04-payment-history-workspace",
            date: "2026-11-04",
            highlights: [
                .init(symbol: "arrow.triangle.2.circlepath", title: "Keep payment history together",
                      detail: "Payment history refresh stops if the saved workspace changes."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-04-estimate-details-before-selection",
            date: "2026-11-04",
            highlights: [
                .init(symbol: "doc.text", title: "Read estimates before choosing",
                      detail: "Customers can read sent estimate details before selecting work."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-04-estimate-material-privacy",
            date: "2026-11-04",
            highlights: [
                .init(symbol: "doc.text", title: "Respect estimate display choices",
                      detail: "Customer estimates group hidden material details while keeping the total visible."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-04-job-money-jumps",
            date: "2026-11-04",
            highlights: [
                .init(symbol: "arrow.up.arrow.down", title: "Find job invoices faster",
                      detail: "Jump to estimates or invoices from a job's Money page."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-03-navigation-routing",
            date: "2026-11-03",
            highlights: [
                .init(symbol: "arrow.turn.up.right", title: "Keep your place",
                      detail: "Links and search open more reliably when your layout changes."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-03-startup-destination",
            date: "2026-11-03",
            highlights: [
                .init(symbol: "rectangle.on.rectangle", title: "Choose your start screen",
                      detail: "Choose where Thorbis opens on this device from Settings."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-03-public-estimate-amounts",
            date: "2026-11-03",
            highlights: [
                .init(symbol: "dollarsign.circle", title: "Clearer estimate amounts",
                      detail: "Customer estimate totals, options and discounts now show the correct dollar amounts."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-03-closeout-payment-evidence",
            date: "2026-11-03",
            highlights: [
                .init(symbol: "checklist", title: "Clearer payment closeout",
                      detail: "Closeout checks known invoices and explains when saved payments need review."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-03-contact-quick-actions",
            date: "2026-11-03",
            highlights: [
                .init(symbol: "person.crop.circle", title: "Reach contacts faster",
                      detail: "Call or text a customer contact directly from their profile."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-03-customer-records-loading",
            date: "2026-11-03",
            highlights: [
                .init(symbol: "person.crop.rectangle.stack", title: "Faster customer records",
                      detail: "Customer histories with several jobs can load more quickly."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-03-job-estimate-status",
            date: "2026-11-03",
            highlights: [
                .init(symbol: "doc.text", title: "See estimate progress",
                      detail: "See which job estimates are drafts or awaiting approval at a glance."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-02-back-alone",
            date: "2026-11-02",
            highlights: [
                .init(symbol: "chevron.backward", title: "One Back button on job pages",
                      detail: "Job, customer and money pages show one round Back button. The menu opens from where you started."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-02-invoice-keyboard-catalog",
            date: "2026-11-02",
            highlights: [
                .init(symbol: "textformat.size", title: "Easier invoice editing",
                      detail: "Close an invoice item and add price book items more easily while the keyboard is open."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-02-customer-estimate-details",
            date: "2026-11-02",
            highlights: [
                .init(symbol: "doc.text", title: "Read estimate details",
                      detail: "Open long item and package details while reviewing work with your customer."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-02-price-book-first-items",
            date: "2026-11-02",
            highlights: [
                .init(symbol: "book", title: "Start with loaded items",
                      detail: "See the first price book items while the rest load, with a clear note when search is incomplete."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-11-02-estimate-text",
            date: "2026-11-02",
            highlights: [
                .init(symbol: "text.alignleft", title: "Keep your estimate wording",
                      detail: "Long item text stays in the editor, with guidance when it needs to be shortened to save."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-02-job-estimate-location",
            date: "2026-11-02",
            highlights: [
                .init(symbol: "doc.text", title: "Create estimates at the job site",
                      detail: "New job estimates use the job’s location, so they can be added to that job."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-02-customer-money-rows",
            date: "2026-11-02",
            highlights: [
                .init(symbol: "doc.text", title: "Find a customer's documents faster",
                      detail: "See each estimate and invoice's reference, status, and available total on the customer page."),
            ],
            fixes: 0
        ),
        ReleaseNote(
            id: "2026-11-02-clear-note-box",
            date: "2026-11-02",
            highlights: [
                .init(symbol: "text.bubble", title: "The note box is easy to spot",
                      detail: "In a job's Activity, the note box has its own edge in light and dark, so you can see where to type."),
                .init(symbol: "creditcard", title: "Done stays off Record payment",
                      detail: "With the number pad up in Collect payment, Done sits above the record button instead of over it."),
            ],
            fixes: 3
        ),
        ReleaseNote(
            id: "2026-11-02-steady-job-page",
            date: "2026-11-02",
            highlights: [
                .init(symbol: "doc.text", title: "Job sections open without a freeze",
                      detail: "Opening Money from far down a job, such as Due on site, shows it from the top and keeps the app moving."),
                .init(symbol: "text.bubble", title: "More room for notes at large text",
                      detail: "With the largest text sizes, quick notes and the note box take less of the screen in Activity."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-11-01-document-status",
            date: "2026-11-01",
            highlights: [
                .init(symbol: "doc.text", title: "Estimates and invoices read the same",
                      detail: "Sent and Unpaid show the same mark on the job, in search and on the estimate or invoice."),
            ],
            fixes: 3
        ),
        ReleaseNote(
            id: "2026-11-01-cream-polish",
            date: "2026-11-01",
            highlights: [
                .init(symbol: "list.bullet", title: "iPad's day reads as one list",
                      detail: "On iPad, today's stops sit together in one list beside the job, not as separate cards."),
            ],
            fixes: 3
        ),
        ReleaseNote(
            id: "2026-11-01-cream-sheet",
            date: "2026-11-01",
            highlights: [
                .init(symbol: "sidebar.left", title: "Every place in the menu",
                      detail: "The menu lists every place you can open, grouped under Work, Money, Shop and On this phone."),
                .init(symbol: "calendar", title: "Today at a glance",
                      detail: "Today shows stops left, what to collect and who is running late, with a map on each stop."),
                .init(symbol: "doc.text", title: "A cleaner job page",
                      detail: "The job sits on one sheet: status, address, Call, Text and Directions, then what to know there."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-11-01-ipad-back-swipe",
            date: "2026-11-01",
            highlights: [
                .init(symbol: "arrow.left", title: "Swipe back beside the list",
                      detail: "On iPad, swipe right from the left edge of a screen next to the list to go back."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-11-01-team-goals",
            date: "2026-11-01",
            highlights: [
                .init(symbol: "flag", title: "Set weekly goals for your team",
                      detail: "Settings › Team goals sets a weekly sold goal per role or person. Works offline."),
                .init(symbol: "chart.bar", title: "See how close you are to your goal",
                      detail: "My scorecard shows your goal and a bar under Sold, plus the leaderboard when it's on."),
                .init(symbol: "list.bullet", title: "Every number opens its list",
                      detail: "Tap Sold, Jobs done or Close rate to see just the invoices, jobs or estimates behind it."),
                .init(symbol: "sun.max", title: "Your week at the top of Today",
                      detail: "Today shows this week's sold and your goal in one row that opens My scorecard."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-01-my-scorecard",
            date: "2026-11-01",
            highlights: [
                .init(symbol: "target", title: "See what you sold this week",
                      detail: "My scorecard in More shows your sold, collected, jobs done, average ticket and close rate."),
            ]
        ),
        ReleaseNote(
            id: "2026-11-01-ipad-reach",
            date: "2026-11-01",
            highlights: [
                .init(symbol: "sidebar.left", title: "Swipe in the iPad sidebar",
                      detail: "Swipe from the left edge to show the sidebar. It also lists saved work waiting to sync."),
                .init(symbol: "hand.draw", title: "Swipe today's jobs on iPad",
                      detail: "On iPad, Schedule rows swipe for Call, Directions and the next step, as on the phone."),
                .init(symbol: "keyboard", title: "Command-F opens search",
                      detail: "Command-F and Command-K open search. On iPad, Control-Command-S and Command-1 to 9 move around."),
            ],
            fixes: 2
        ),
        ReleaseNote(
            id: "2026-11-01-ipad-pass",
            date: "2026-11-01",
            highlights: [
                .init(symbol: "ipad.landscape", title: "Calmer iPad layout",
                      detail: "The iPad sidebar matches the menu, and Inbox and Money keep their buttons beside what they act on."),
                .init(symbol: "keyboard", title: "Keyboard shortcuts in Slide Over",
                      detail: "With a keyboard, Command-F searches and Command-N starts a new job in any window size."),
            ],
            fixes: 2
        ),
        ReleaseNote(
            id: "2026-11-01-forms-say-whats-missing",
            date: "2026-11-01",
            highlights: [
                .init(symbol: "text.cursor", title: "Forms say what's missing",
                      detail: "Save buttons stay on. Press one early and the form names what's missing under the field."),
            ],
            fixes: 3
        ),
        ReleaseNote(
            id: "2026-10-31-ownership-transfer",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "key", title: "Hand the company to a new owner",
                      detail: "Owners can make a teammate the owner from their Team page. You stay on as an admin."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-member-savings",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "tag", title: "Members see what they save",
                      detail: "Estimates and invoices show a Member savings line above the total when member prices apply."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-row-swipes",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "hand.draw", title: "Swipe jobs for Call and the next step",
                      detail: "Swipe a job right to call or get directions, left for its next step. Swipe a notice right to open its job."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-stop-cards",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "rectangle.stack", title: "Swipe through today's stops",
                      detail: "Today opens on your current stop as a card. Swipe for the next one; the list toggle is beside the tabs."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-thorbis-design",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "paintbrush", title: "A calmer look with smaller type",
                      detail: "Quieter colors and type, status as a word, and menus that open right where you tap instead of a sheet."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-drawer-menu",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "sidebar.left", title: "A simpler side menu, on every screen",
                      detail: "Your main places, recent jobs and New job. More is under All places; the menu circle sits beside Back."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-redesign",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "sparkles", title: "A fresh, easier-to-navigate look",
                      detail: "Labeled tabs, a More list of every place, and a Today view with status rings and grouped sections."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-history-polish",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "clock.arrow.circlepath", title: "Read a job's whole story",
                      detail: "Activity now lists calls and estimates by day, and long notes open with More instead of getting cut off."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-customer-view-polish",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "person.crop.rectangle", title: "A clearer estimate for customers",
                      detail: "Customers can step back to the options from a round button, and job section amounts never get cut off."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-onsite-polish",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "wrench.and.screwdriver", title: "A cleaner on-site screen",
                      detail: "Tool names wrap instead of shrinking, and the status line and Wrap up button read cleanly at large text."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-large-text-voiceover",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "textformat.size", title: "Easier with large text and VoiceOver",
                      detail: "Customer actions and site notes fit at large text. Contacts and invoice lines read as one item."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-mockup-parity",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "list.bullet.rectangle", title: "Tidier rows and estimate lines",
                      detail: "Each estimate line shows its name, then what it covers. Share job now sits in the job's ••• menu."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-onsite-wrap-up",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "checklist", title: "See what's left before you wrap up",
                      detail: "Photos, note, approval, signature and payment tick off as you go. Tap one to do it, then complete."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-search-redesign",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "magnifyingglass", title: "Find anything faster",
                      detail: "Search by street, name, phone or number, start a job from search, and find saved work with no signal."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-media-before-after",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "rectangle.split.2x1", title: "Faster photos with Before/After compare",
                      detail: "Tag each shot Before or After as you go, shoot in bursts, and show the customer a side-by-side."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-builder-redesign",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "cart", title: "Faster estimates from the price book",
                      detail: "Add several items at once, star favourites, and edit a line in place. Copy an option to start the next."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-customer-states",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "person.text.rectangle", title: "Friendlier screens for customers",
                      detail: "Customer view loads and errors in large, plain words. Next stop says when Location is off."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-first-run-states",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "rectangle.and.text.magnifyingglass", title: "Clearer sign-in, empty and error screens",
                      detail: "Every empty list says what to do next, and every error says what went wrong and how to fix it.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-next-stop-lock-screen",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "lock.rectangle", title: "Your next stop on the lock screen",
                      detail: "Widgets, the lock screen card and Control Center show the street and the next step: On my way, Arrived, Start.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-book-job-board",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "phone.arrow.down.left", title: "Book a job in seconds",
                      detail: "Search the caller by name, phone or address, pick a time and a suggested tech. Board shows every tech's day.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-owner-home",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "house", title: "See how today is going at a glance",
                      detail: "Owners open on Home: today's jobs by state, money, what needs you and where each tech is.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-offline-day",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "wifi.slash", title: "More of your day works without signal",
                      detail: "Today's jobs, customers, estimates and invoices open offline, and follow-ups send once you're back.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-ipad-layout",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "rectangle.split.3x1", title: "A proper iPad layout",
                      detail: "A sidebar of places, lists beside jobs and customers, a week board, and ⌘F search and ⌘N new job.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-31-polish-tech-flow",
            date: "2026-10-31",
            highlights: [
                .init(symbol: "sparkles", title: "A tidier visit, start to finish",
                      detail: "Wrap up, Money, payment and the customer profile line up better, and large text no longer crowds them.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-review-requests",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "star.bubble", title: "Ask paid customers for a review",
                      detail: "Add your review link in Settings. Customers get one text after paying, never twice in 90 days."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-morning-digest",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "sun.max", title: "Start the day with one summary",
                      detail: "Owners get one 6:30 note: yesterday's collections, today's jobs and overdue invoices. Turn it off in Notices."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-hours-tax-terms",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "clock", title: "Hours, tax and terms in setup",
                      detail: "Set your open hours, time zone, sales tax rate and payment terms. Saved offline too."),
                .init(symbol: "photo", title: "Add your logo",
                      detail: "Pick your company logo from Photos in setup or in Company details."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-call-log",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "phone.badge.waveform", title: "Calls in your Inbox",
                      detail: "Hear each call to your business, read its summary and link it to the job it booked."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-job-equipment-for-techs",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "shippingbox", title: "Equipment and membership on your jobs",
                      detail: "Techs on a job now see the units installed there and the customer's member discount."),
            ]
        ),
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
            id: "2026-10-30-work-offline",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "wifi.slash", title: "Wrap up a job with no signal",
                      detail: "Confirm the checklist and complete the job offline. It all sends once you're back online."),
                .init(symbol: "banknote", title: "Take cash or a check offline",
                      detail: "The payment waits on the invoice and records itself the moment you have signal again."),
                .init(symbol: "signature", title: "Customers can sign without signal",
                      detail: "The signature is kept on your phone and added to the invoice when you reconnect."),
                .init(symbol: "arrow.triangle.2.circlepath", title: "One line shows what's waiting",
                      detail: "The top of the app counts changes and photos still on your phone, then says when they've synced."),
            ],
            fixes: 0
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
            id: "2026-10-30-dark-and-large-text",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "textformat.size", title: "Clearer in dark mode and large text",
                      detail: "Red and blue words read clearly in dark mode, and big text sizes wrap instead of running off the screen.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-redesign-remaining-screens",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "square.grid.2x2", title: "Every screen in the new look",
                      detail: "Settings, reports, forms, price book, follow-ups and the iPad schedule now match the job screen.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-job-onsite-redesign",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "wrench.and.screwdriver", title: "Everything for the visit in one place",
                      detail: "Once you arrive, the job shows your tools, gate codes and what's left before you wrap up.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-onsite-tools",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "barcode.viewfinder", title: "Scan equipment tags and run checklists",
                      detail: "Read the model and serial off a tag into the job's notes, and tick off checklists with readings."),
                .init(symbol: "video", title: "Record short video clips on a job",
                      detail: "Add a clip of up to a minute to the job's documents. It uploads when you have signal.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-read-every-line",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "doc.text.magnifyingglass", title: "Read every line before you sign",
                      detail: "Estimates show each line's full description, and customers see what's included before they approve.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-cleaner-lists",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "list.bullet", title: "Cleaner lists everywhere",
                      detail: "Today leads with the street, statuses read as words, and customers open on one tidy page.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-voice-notes",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "mic", title: "Talk or tap to write job notes",
                      detail: "Dictate a note with the mic, or tap a common phrase like Photos added, then edit before saving.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-next-stop",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "car", title: "See your next stop at a glance",
                      detail: "Schedule opens on where you're headed, the drive time and Directions, On my way and Call in one tap.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-before-you-go-in",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "house", title: "Know the place before you go in",
                      detail: "Jobs show gate codes, pets, equipment and the last three visits there, even offline.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-ux-cleanup-leftovers",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "magnifyingglass", title: "Search starts where you are",
                      detail: "Open search on Jobs or Customers and the jobs or customers you opened lately come first."),
                .init(symbol: "person.text.rectangle", title: "Customer details always showing",
                      detail: "Address, phone and email sit open on the customer page, with New job as the one button."),
                .init(symbol: "hand.tap", title: "Tap anywhere on an option to choose it",
                      detail: "In the customer's estimate, each option card is one big target with its price first."),
            ],
            fixes: 3
        ),
        ReleaseNote(
            id: "2026-10-30-calm-job",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "rectangle.split.3x1", title: "Jobs now have three tabs",
                      detail: "Estimates and invoices share Money, photos sit in Activity, and the other tabs keep a one-line header.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-customer-view",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "person.crop.rectangle", title: "One Customer view for each job",
                      detail: "Hand over the phone once for every estimate to approve, each invoice and the customer's own details.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-search-create",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "plus.magnifyingglass", title: "One search, one + and quicker booking",
                      detail: "Search from the bar, start a job, estimate or customer from +, and book unscheduled jobs right from the list.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-visual-rollout",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "rectangle.grid.1x2", title: "Clearer lists on every screen",
                      detail: "Jobs, customers, money and team lists sit in tidy groups with an icon and status in words.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-nav-by-role",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "person.crop.circle.badge.checkmark", title: "Your day and your places, by role",
                      detail: "Techs open on their own jobs, the bar fits your role, and Settings, Money and reports each live in one place.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-job-customer-links",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "person.crop.rectangle.stack", title: "Open a job's customer and contacts",
                      detail: "Jobs list every contact and address with Call, Text and Directions, and open the customer.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-custom-buttons",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "circle.circle", title: "Clearer buttons on every screen",
                      detail: "Back, share, more, Done and Cancel now use Thorbis buttons that match the menu and filters."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-calendar-contacts-mail",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "calendar.badge.plus", title: "Add visits to Calendar and Contacts",
                      detail: "Put a scheduled visit on your calendar, save customers to Contacts and email them from Mail.")
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-siri-spotlight",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "magnifyingglass", title: "Find jobs with Siri and Spotlight",
                      detail: "Ask Siri for your next job or schedule, and find your jobs and customers in Spotlight."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-lock-screen-controls",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "lock", title: "Update a job from the Lock Screen",
                      detail: "Tap On my way, Mark arrived or Start work on the job card; without signal it waits to sync."),
                .init(symbol: "calendar.badge.clock", title: "See your next job at a glance",
                      detail: "Lock Screen widgets show your next job's time, customer and how many jobs are left today."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-photo-markup-measure",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "pencil.tip.crop.circle", title: "Mark up job photos",
                      detail: "Draw on a copy of a job photo; the marked-up copy is added to the job and the original stays."),
                .init(symbol: "ruler", title: "Measure on site",
                      detail: "Tap two points with the camera to measure, then save the photo with the distance to the job."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-tablet-invoice",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "doc.plaintext", title: "Invoices open from iPad Schedule",
                      detail: "On iPad, a job's invoice opens from Schedule and stays the one you picked when you come back."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-faster-lists",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "list.bullet", title: "Move through lists faster",
                      detail: "Customer lists and repeated price book searches do less work as you browse."),
                .init(symbol: "photo.on.rectangle", title: "Browse job photos sooner",
                      detail: "Open photos sooner and load more as you browse."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-document-description-reading",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "text.alignleft", title: "Read full document details",
                      detail: "Open long estimate and invoice descriptions in a clear reading view."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-job-document-clarity",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "doc.text", title: "Find job documents faster",
                      detail: "Recognize estimates and invoices in the job and open each for its details."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-setup-check-retry",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "arrow.clockwise", title: "Retry setup checks",
                      detail: "See when a setup step couldn't be checked and try again."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-inbox-day-groups",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "calendar", title: "Find notices by day",
                      detail: "Inbox notices are grouped by date, with unread notices clearly marked."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-pricebook-visual-cues",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "book.closed", title: "Recognize price book items",
                      detail: "See material and service markers with clearer names and prices."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-photo-date-groups",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "photo.on.rectangle", title: "Find job photos by date",
                      detail: "Browse photos by capture date, with undated photos kept together."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-customer-action-text",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "textformat.size", title: "Clearer customer actions",
                      detail: "Customer action labels have room to wrap at larger text sizes."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-invoice-balance-wording",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "doc.text", title: "Clearer invoice balances",
                      detail: "See when an invoice is a draft, has no balance due, or is paid."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-readonly-handback",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "hand.wave", title: "Hand back reviewed documents",
                      detail: "Return the phone to your technician after viewing a changed document."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-estimate-documents-return",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "doc.on.doc", title: "Keep reviewing job documents",
                      detail: "Return to the job's documents after reviewing or approving an estimate."),
                .init(symbol: "hand.wave", title: "Hand back after invoice review",
                      detail: "Return the phone to your technician after reviewing an invoice."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-inbox",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "bell", title: "See new notices clearly",
                      detail: "Unread inbox items are easier to spot and open."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-30-visual-cues",
            date: "2026-10-30",
            highlights: [
                .init(symbol: "calendar", title: "Scan your schedule faster",
                      detail: "Visit markers show each job's status alongside its time and details."),
                .init(symbol: "doc.text", title: "Recognize documents at a glance",
                      detail: "Estimates, invoices and billing schedules have clearer visual markers."),
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
            id: "2026-10-29-customer-visual",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "person.crop.square", title: "See the next visit clearly",
                      detail: "Customer profiles make the next visit easier to find and open."),
                .init(symbol: "briefcase", title: "Find your work faster",
                      detail: "Search jobs from the list and see job sections more clearly."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-pricebook-at-a-glance",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "book.closed", title: "Scan the price book faster",
                      detail: "See clear item names and prices, then open an item for its full details."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-job-glance",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "briefcase", title: "Find visit details faster",
                      detail: "Find notes, photos and follow-ups near the top of a job."),
                .init(symbol: "person.crop.circle", title: "See customers at a glance",
                      detail: "Find the next visit and contact actions, with all jobs in one place."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-pricebook-pages",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "book.closed", title: "Browse more price book items",
                      detail: "Move through all loaded matching items when building an estimate or editing an invoice."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-customer-job-history",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "photo.on.rectangle", title: "See customer photos by job",
                      detail: "Browse photos from each job together on the customer profile."),
                .init(symbol: "map", title: "Choose a customer location",
                      detail: "Pick the right location for directions instead of assuming a job site."),
            ],
            fixes: 2
        ),
        ReleaseNote(
            id: "2026-10-29-catalog-editing",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "book.closed", title: "Edit while adding invoice items",
                      detail: "Adjust the last added line without leaving the price book."),
                .init(symbol: "list.bullet", title: "Review estimates from the catalog",
                      detail: "Return to your estimate and its items directly from search."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-10-29-job-estimate-layout",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "doc.text", title: "Scan job estimates faster",
                      detail: "See the work, price and status first, with totals and actions close at hand."),
            ],
            fixes: 0
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
                .init(symbol: "book.closed", title: "Edit invoice lines in the price book",
                      detail: "Search the price book on an invoice draft, then adjust or remove items."),
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
            id: "2026-10-29-job-estimate-handoff",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "doc.on.doc", title: "Present every job estimate",
                      detail: "Show the job's estimates together, with each price and status clearly visible."),
                .init(symbol: "signature", title: "Approve several estimates",
                      detail: "Choose separate estimates in one handoff, then review and sign each without starting over."),
            ],
            fixes: 3
        ),
        ReleaseNote(
            id: "2026-10-29-saved-work-review",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "arrow.triangle.2.circlepath", title: "Review saved work in one place",
                      detail: "See waiting changes, photos and scans by job, then open the job or retry from one review."),
            ],
            fixes: 2
        ),
        ReleaseNote(
            id: "2026-10-29-photo-recovery-cleanup",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "arrow.clockwise", title: "Finish older photo recovery",
                      detail: "Completed uploads clean up matching older files without leaving an unnecessary recovery warning."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-29-durable-job-media",
            date: "2026-10-29",
            highlights: [
                .init(symbol: "doc.viewfinder", title: "Keep scans when you're offline",
                      detail: "Scanned job documents and photos stay on this phone until their upload is confirmed."),
                .init(symbol: "photo.on.rectangle", title: "Keep saved work in its workspace",
                      detail: "Switch workspaces without mixing waiting files, and see which uploads need attention."),
                .init(symbol: "arrow.clockwise", title: "Recover older saved photos",
                      detail: "Review older photos for this job, confirm the destination, then retry their upload."),
            ],
            fixes: 4
        ),
        ReleaseNote(
            id: "2026-10-28-job-document-book",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "doc.on.doc", title: "Swipe through the job's documents",
                      detail: "Browse every estimate and invoice, or use Previous, Next and All documents to choose one."),
                .init(symbol: "banknote", title: "See discounts, payments and refunds",
                      detail: "Each invoice shows its own discounts, dated payments, refunds and remaining balance."),
                .init(symbol: "signature", title: "Keep your place while reviewing",
                      detail: "Open a separate review or signature, then return to the document you were reading."),
            ],
            fixes: 8
        ),
        ReleaseNote(
            id: "2026-10-28-customer-review",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "doc.text.magnifyingglass", title: "Review the exact estimate",
                      detail: "Customers see the issued work and price before signing, with a clear retry if it can't be opened."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-28-invoice-catalog",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "magnifyingglass", title: "Search your full catalog on invoices",
                      detail: "Find services and materials as you type, with recent items and category filters close by."),
                .init(symbol: "plus.circle", title: "Add several items without going back",
                      detail: "Keep searching and adding, see the quantity in your draft, then tap Done when you're ready."),
            ],
            fixes: 5
        ),
        ReleaseNote(
            id: "2026-10-28-job-documents",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "doc.on.doc", title: "Every document for the job",
                      detail: "See each estimate and invoice for this job, with its own price, status and details."),
                .init(symbol: "person.crop.rectangle", title: "Show customers their job documents",
                      detail: "Browse estimates and invoices together, then unlock to return to the technician's tools."),
                .init(symbol: "sum", title: "See estimate totals at a glance",
                      detail: "Expand totals for approved work and estimates awaiting approval, with pricing options kept separate."),
            ],
            fixes: 1
        ),
        ReleaseNote(
            id: "2026-10-28-invoice-scan-to-pay",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "qrcode", title: "Let customers scan to pay",
                      detail: "Show a QR code for secure card checkout, or share the link with the customer."),
                .init(symbol: "banknote", title: "Record money already received",
                      detail: "Cash and check stay close. Find bank transfers and cards collected elsewhere in one menu."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-28-tap-readiness",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "creditcard", title: "Payment choices that are ready to use",
                      detail: "Collection starts with a secure link when Tap to Pay is not ready for this version."),
            ]
        ),
        ReleaseNote(
            id: "2026-10-28-readable-controls",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "textformat.size", title: "Read buttons at your text size",
                      detail: "Buttons, tabs and job labels grow with your text, and contact shortcuts stack at larger sizes."),
                .init(symbol: "phone", title: "Listen to the booking call",
                      detail: "Play the booking call, read its summary, or open the transcript from the job."),
            ],
            fixes: 3
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
