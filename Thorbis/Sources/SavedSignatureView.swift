import SwiftUI

/// Paper 65D "Saved signature" (Settings › Work preferences): the person's own signature on a
/// card with their name and the day it was saved, Redraw, and Delete signature at the foot.
///
/// Paper also draws a "Use on wrap-ups automatically" switch. Nothing in the app asks the
/// technician to sign today (estimates and invoices are signed by the customer), so the switch is
/// left out rather than shown doing nothing, and the page says what the signature is kept for.
struct SavedSignatureView: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var store: SavedSignatureStore?
    @State private var signature: SavedSignature?
    @State private var drawing = false
    @State private var confirmDelete = false
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved signature").font(Theme.font(28, weight: .bold)).tracking(-0.56)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your sign-off, kept on this phone").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4).padding(.top, 14).padding(.bottom, 16)
                if let problem {
                    Text(problem).font(Theme.font(15)).foregroundStyle(Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.bottom, 12)
                        .accessibilityIdentifier("saved-signature-problem")
                }
                PaperCard {
                    if let signature {
                        SavedSignatureDrawing(signature: signature)
                        WellDivider(leading: 0)
                    } else {
                        LearnEmptyRow(title: "No signature saved",
                                      message: "Draw it once with your finger and it stays on this phone.")
                            .accessibilityIdentifier("saved-signature-empty")
                        WellDivider(leading: 0)
                    }
                    Button { drawing = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "pencil").font(.system(size: 16, weight: .medium)).accessibilityHidden(true)
                            Text(signature == nil ? "Draw signature" : "Redraw").font(Theme.font(16, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.muted).accessibilityHidden(true)
                        }
                        .foregroundStyle(Theme.brandText)
                        .padding(.horizontal, PaperCardMetrics.inset)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .disabled(store == nil)
                    .accessibilityIdentifier("saved-signature-draw")
                }
                VStack(alignment: .leading, spacing: 8) {
                    // Paper's line, then what is true today.
                    Text("Customers still sign for themselves. Your signature only shows who did the work.")
                    Text("Nothing in Thorbis adds it to a job or a document yet. It is saved on this phone only, in a protected file, and is never used as a customer\u{2019}s signature.")
                }
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).padding(.top, 12)
                if signature != nil {
                    Button { confirmDelete = true } label: {
                        Text("Delete signature").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .padding(.top, 32)
                    .accessibilityIdentifier("saved-signature-delete")
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 32)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("saved-signature")
        .task(id: session.user?.id) { open() }
        .sheet(isPresented: $drawing) {
            SheetSurface {
                SavedSignatureDrawSheet(signerName: signerName) { strokes, size in
                    guard let store else { throw Problem(title: "Sign in to save a signature", status: nil, detail: nil) }
                    signature = try store.save(strokes: strokes, padSize: size, signerName: signerName)
                    problem = nil
                }
            }
        }
        .thorbisConfirm("Delete your saved signature?",
                        message: "It is removed from this phone. You can draw it again any time.",
                        isPresented: $confirmDelete,
                        actions: [ThorbisConfirmAction("Delete signature", role: .destructive) {
                            do { try store?.clear(); signature = nil; problem = nil }
                            catch { problem = "The signature was not deleted. \(error.localizedDescription)" }
                        }])
    }

    private var signerName: String { session.user?.name ?? session.user?.email ?? "" }

    private func open() {
        guard let actor = session.user?.id else {
            store = nil; signature = nil
            return
        }
        do {
            let opened = try SavedSignatureStore(actorID: actor)
            store = opened
            signature = opened.signature
            problem = nil
        } catch {
            store = nil; signature = nil
            problem = "The saved signature could not be opened. \(error.localizedDescription)"
        }
    }
}

/// The signature on its card: the ink over a line, the name under it and when it was saved.
private struct SavedSignatureDrawing: View {
    let signature: SavedSignature

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                for stroke in SavedSignatureInk.fit(signature.strokes, in: size) {
                    context.stroke(SignatureInk.path(stroke), with: .color(Theme.foreground), style: SignatureInk.style)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 110)
            .accessibilityHidden(true)
            Rectangle().fill(Theme.muted).frame(height: 1).accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(signature.signerName.isEmpty ? "Your signature" : signature.signerName)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(SavedSignatureInk.savedLabel(signature.savedAt)).monospacedDigit()
            }
            .font(Theme.font(13)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your signature, \(SavedSignatureInk.savedLabel(signature.savedAt).lowercased())")
        .accessibilityIdentifier("saved-signature-ink")
    }
}

/// Draw with a finger: the same pad customers sign on, Clear, and Save.
private struct SavedSignatureDrawSheet: View {
    let signerName: String
    let onSave: ([[CGPoint]], CGSize) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var padSize = CGSize.zero
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            LearnEditorHeader(title: "Draw your signature", saveIdentifier: "saved-signature-save",
                              onCancel: { dismiss() }, onSave: save)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sign above the line").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { strokes = []; problem = nil } label: {
                        Text("Clear").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(strokes.isEmpty)
                    .accessibilityLabel("Clear the drawing")
                    .accessibilityIdentifier("saved-signature-clear")
                }
                .padding(.horizontal, 4)
                SignaturePad(strokes: $strokes, ink: Theme.brand, surface: Theme.card, onStroke: { problem = nil })
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.muted).frame(height: 1)
                            .padding(.horizontal, 24).padding(.bottom, 44)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { padSize = $0 }
                    .accessibilityLabel("Signature pad")
                    .accessibilityHint("Draw your signature with one finger")
                    .accessibilityIdentifier("saved-signature-pad")
                if let problem { FieldProblem(message: problem).padding(.horizontal, 4) }
                LearnFootnote(text: signerName.isEmpty ? "Saved on this phone only."
                                                       : "Saved on this phone only, as \(signerName).")
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        // Dragging on the pad draws; it must not also pull the sheet down.
        .interactiveDismissDisabled(!strokes.isEmpty)
    }

    private func save() {
        guard SignatureInk.hasInk(strokes) else { problem = "Draw your signature to save it."; return }
        do { try onSave(strokes, padSize); dismiss() }
        catch { problem = error.localizedDescription }
    }
}
