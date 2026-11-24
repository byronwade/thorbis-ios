import SwiftUI

/// Paper F4A "Recording voice note": a bottom sheet over the job while the phone listens. A red
/// "Recording" pill, the time so far in 48 Bold, what to say, the words as they are heard on a
/// card, then Discard and the red Stop. The words fill the job's note draft; Stop hands it to the
/// note field to check and save. Paper's waveform and Pause are left out (the phone's dictation
/// gives no level and can't pause), and Paper's last line promises drafted parts, which nothing
/// here does, so the line says what really happens.
struct JobVoiceNoteSheet: View {
    @ObservedObject var dictation: NoteDictation
    /// The draft the words go into (earlier text, then what is heard).
    let text: String
    /// What was in the draft before recording began: only what comes after it is shown as heard.
    let before: String
    let started: Date
    let onDiscard: () -> Void
    let onStop: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var height: CGFloat = 520

    private var heard: String {
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = before.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lead.isEmpty, whole.hasPrefix(lead) else { return whole }
        return String(whole.dropFirst(lead.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.destructive).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(dictation.isListening ? "Recording" : "Stopped").font(Theme.font(13, weight: .semibold))
                        .foregroundStyle(Theme.destructive)
                }
                .padding(.horizontal, 12).frame(minHeight: 28)
                .background(Theme.destructiveSurface, in: Capsule())
                .accessibilityElement(children: .combine)
                TimelineView(.periodic(from: started, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(started)))
                    Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                        .font(Theme.font(48, weight: .bold)).tracking(-1.2)
                        .accessibilityLabel("\(seconds / 60) minutes \(seconds % 60) seconds")
                }
                .padding(.top, 6)
                Text("Say what you found and what you used").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Live transcript").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.ai)
                    if let problem = dictation.problem {
                        Text(problem.message).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(heard.isEmpty ? (dictation.isListening ? "Listening\u{2026}" : "Nothing heard yet.") : heard)
                            .font(Theme.font(17, weight: .medium))
                            .foregroundStyle(heard.isEmpty ? Theme.muted : Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 20)
                .accessibilityElement(children: .combine)
                ZStack {
                    HStack {
                        Button(action: onDiscard) {
                            VStack(spacing: 8) {
                                PaperIcon(.jobTrash, size: 18).frame(width: 52, height: 52).background(Theme.quietFill, in: Circle())
                                Text("Discard").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            }
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("voice-note-discard")
                        .padding(.leading, 30)
                        Spacer(minLength: 0)
                    }
                    Button(action: onStop) {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white).frame(width: 26, height: 26)
                                .frame(width: 84, height: 84).background(Theme.destructiveFill, in: Circle())
                            Text("Stop").font(Theme.font(15, weight: .semibold))
                        }
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityHint("Puts the words in the note to check")
                    .accessibilityIdentifier("voice-note-stop")
                }
                .padding(.top, 24)
                Text("When you stop, the words go into the note for you to check.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Theme.foreground)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .accessibilityIdentifier("voice-note-sheet")
    }
}
