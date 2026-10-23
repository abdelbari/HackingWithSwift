// Adjust photo: the picture in a text's letters moved and zoomed by hand.
//
// The box is drawn as the canvas draws it, fitted to the sheet, and a drag
// slides the photo with the finger — its focus moving against the picture's
// slack (PhotoFills.moved) — while a pinch zooms it in or out
// (PhotoFills.zoomed), each gesture one undo step as it ends. Remove photo
// gives the letters their colour back. Beside it, the questions a photo
// in letters asks: "Fill the letters?" when one is dropped on a selected
// text box, and Adjust photo offered when filled letters are
// double-tapped. The Android twin's Adjust photo bar, in the same words.

import SwiftUI

struct PhotoInLettersSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    /// The paint as the drag or pinch began, which every tick moves from.
    @State private var startPaint: Paint?

    private var element: Element? {
        store.photoAdjustTarget.flatMap { store.element($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(DesignStore.adjustPhotoNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let el = element {
                    preview(el)
                } else {
                    Text(DesignStore.photoCannotOpen)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    store.removePhotoFromLetters()
                    dismiss()
                } label: {
                    Label(DesignStore.removePhoto, systemImage: "photo.badge.minus")
                }
                .frame(minHeight: 44)
                Spacer()
            }
            .padding()
            .navigationTitle(DesignStore.adjustPhotoTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear {
            store.endPhotoAdjust()
            store.photoAdjustTarget = nil
        }
    }

    /// The box as the canvas draws it, scaled to fit, taking the drag and
    /// the pinch; the scale turns the finger's points into the box's own.
    private func preview(_ el: Element) -> some View {
        GeometryReader { proxy in
            let scale = Self.fit(el, in: proxy.size)
            ElementView(element: el)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: el.w * scale, height: el.h * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(drag(scale: scale))
                .simultaneousGesture(pinch)
                .accessibilityLabel(DesignStore.adjustPhotoTitle)
        }
        .frame(height: 260)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    /// The scale that fits the box inside `size`, never enlarging it past
    /// twice its own size.
    static func fit(_ el: Element, in size: CGSize) -> Double {
        guard el.w > 0, el.h > 0, size.width > 0, size.height > 0 else { return 1 }
        return min(Double(size.width) / el.w, Double(size.height) / el.h, 2)
    }

    private func drag(scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if startPaint == nil { startPaint = store.adjustedPhoto }
                guard let start = startPaint else { return }
                store.movePhotoInLetters(from: start, dx: Double(value.translation.width) / max(scale, 1e-6),
                                         dy: Double(value.translation.height) / max(scale, 1e-6))
            }
            .onEnded { _ in
                startPaint = nil
                store.endPhotoAdjust()
            }
    }

    private var pinch: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if startPaint == nil { startPaint = store.adjustedPhoto }
                guard let start = startPaint else { return }
                store.zoomPhotoInLetters(from: start, by: Double(value))
            }
            .onEnded { _ in
                startPaint = nil
                store.endPhotoAdjust()
            }
    }
}

/// The questions a photo in letters asks, over the editor: a photo dropped
/// on a selected text box ("Fill the letters?"), and filled letters
/// double-tapped (Adjust photo, Edit text or Remove photo).
struct PhotoInLettersPrompts: ViewModifier {
    @Bindable var store: DesignStore
    /// The sheet to open for Adjust photo.
    var openAdjust: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(DesignStore.fillLettersQuestion, isPresented: fillAsked, titleVisibility: .visible) {
                Button(DesignStore.fillLetters) { store.acceptLetterFill() }
                // The photo already counts as dropped, so going away keeps it
                // on the page, as on Android: Keep the photo is the cancel.
                Button(DesignStore.keepPhoto, role: .cancel) { store.declineLetterFill() }
            } message: {
                Text(DesignStore.fillLettersNote)
            }
            .confirmationDialog(DesignStore.adjustPhotoTitle, isPresented: adjustOffered, titleVisibility: .visible) {
                Button(DesignStore.adjustPhotoTitle) {
                    if let id = store.photoAdjustOffer, store.startPhotoAdjust(id) { openAdjust() }
                    store.photoAdjustOffer = nil
                }
                Button("Edit text") {
                    if let id = store.photoAdjustOffer { store.startTyping(id) }
                    store.photoAdjustOffer = nil
                }
                Button(DesignStore.removePhoto, role: .destructive) {
                    if let id = store.photoAdjustOffer { store.selection = [id] }
                    store.removePhotoFromLetters()
                    store.photoAdjustOffer = nil
                }
                Button("Cancel", role: .cancel) { store.photoAdjustOffer = nil }
            }
    }

    private var fillAsked: Binding<Bool> {
        // Dismissed any other way, the photo is kept too — after the tapped
        // button's own action, which has taken the offer by then if it was
        // Fill the letters.
        Binding(get: { store.letterFillOffer != nil }, set: { shown in
            if !shown { Task { @MainActor in store.declineLetterFill() } }
        })
    }

    private var adjustOffered: Binding<Bool> {
        Binding(get: { store.photoAdjustOffer != nil }, set: { if !$0 { store.photoAdjustOffer = nil } })
    }
}
