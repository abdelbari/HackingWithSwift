// Copy & resize, ticked: the design types, the sizes last made here and a
// size typed, each a checkbox, and one button that makes a copy per size —
// "Make 3 copies" — while "Making copy 2 of 3…" says how far it has got.
// Inside the editor's Resize sheet, and on its own from a Home card's menu.

import SwiftUI

/// The sizes as checkboxes, in sections of a List.
struct CopyResizeRows: View {
    @Binding var ticked: [ResizeTarget]
    @State private var customW = ""
    @State private var customH = ""
    @State private var unit = "px"
    /// Read once as the rows appear.
    @State private var recent = CustomSizes.recent()

    var body: some View {
        Section("Design types") {
            ForEach(SizePreset.all) { preset in
                checkRow(.preset(preset), title: preset.name, detail: preset.dimensions, icon: preset.icon)
            }
        }
        if !recent.isEmpty {
            Section("Recently used") {
                ForEach(recent, id: \.self) { size in
                    let target = ResizeTarget.custom(width: Double(size.width), height: Double(size.height), unit: "px")
                    checkRow(target, title: target.label, detail: "Custom", icon: "clock")
                }
            }
        }
        customSection
    }

    private var customSection: some View {
        let size = CustomSizes.size(width: customW, height: customH, unit: unit)
        // Sizes typed here and ticked, under the fields they came from.
        let typed = ticked.filter { t in
            t.name == nil && !recent.contains { Double($0.width) == t.width && Double($0.height) == t.height && t.unit == nil }
        }
        return Section {
            UnitPicker(unit: $unit)
                .onChange(of: unit) { old, new in
                    customW = CustomSizes.convert(customW, from: old, to: new)
                    customH = CustomSizes.convert(customH, from: old, to: new)
                }
            HStack {
                TextField("Width", text: $customW).keyboardType(unit == "px" ? .numberPad : .decimalPad)
                Text("×")
                TextField("Height", text: $customH).keyboardType(unit == "px" ? .numberPad : .decimalPad)
                Text(unit).foregroundStyle(.secondary)
            }
            Button {
                guard let size else { return }
                let target = ResizeTarget.custom(width: size.width, height: size.height, unit: unit)
                if !ticked.contains(target) { ticked.append(target) }
                customW = ""
                customH = ""
            } label: {
                Label(size.map { "Add \(CustomSizes.title(width: $0.width, height: $0.height, unit: unit))" }
                      ?? "Enter a size from \(CustomSizes.rangeText)", systemImage: "plus.circle")
            }
            .disabled(size == nil)
            ForEach(typed) { target in
                checkRow(target, title: target.label, detail: "Custom", icon: "slider.horizontal.3")
            }
        } header: {
            Text("Custom")
        } footer: {
            let wrong = !customW.isEmpty && CustomSizes.side(customW, unit: unit) == nil
                || !customH.isEmpty && CustomSizes.side(customH, unit: unit) == nil
            Text(wrong ? CustomSizes.outOfRangeText : "Each side \(CustomSizes.rangeText).")
                .foregroundStyle(wrong ? Color(.systemRed) : Color.secondary)
        }
        .onChange(of: customW) { _, typed in
            let clean = CustomSizes.field(typed, unit: unit)
            if clean != typed { customW = clean }
        }
        .onChange(of: customH) { _, typed in
            let clean = CustomSizes.field(typed, unit: unit)
            if clean != typed { customH = clean }
        }
    }

    private func checkRow(_ target: ResizeTarget, title: String, detail: String, icon: String) -> some View {
        let on = ticked.contains(target)
        return Button {
            if on { ticked.removeAll { $0 == target } } else { ticked.append(target) }
        } label: {
            HStack {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.accent : Color.secondary)
                    .font(.title3)
                Label(title, systemImage: icon)
                Spacer()
                Text(detail)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("\(title), \(detail.replacingOccurrences(of: " × ", with: " by "))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The button under the sizes: "Make 3 copies", then how far it has got.
struct CopyResizeButton: View {
    let count: Int
    let progress: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if progress != nil { ProgressView().tint(.white) }
                Text(progress ?? CopyResize.buttonTitle(count: max(count, 0)))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(count == 0 || progress != nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

extension CopyResize {
    /// The copies of `source` at `targets`, titled against the shelf, saved
    /// with their pictures; "Making copy 2 of 3…" told to `progress`.
    @MainActor
    static func make(_ source: Design, targets: [ResizeTarget],
                     progress: @escaping (String) -> Void) async throws -> [Design] {
        let taken = await Task.detached(priority: .userInitiated) {
            DesignLibrary.recents().map(\.title)
        }.value
        let made = copies(of: source, to: targets, taken: taken)
        return try await save(made) { n in progress(CopyResize.progressText(n, of: made.count)) }
    }
}

/// Copy & resize from a Home card: the same rows and button, for a design
/// that is not open.
struct CopyResizeSheet: View {
    let source: Design
    var onDone: ([Design]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ticked: [ResizeTarget] = []
    @State private var progress: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Makes a new design for each size ticked, reflowed to fit, in the same folder. “\(source.title)” stays as it is.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                CopyResizeRows(ticked: $ticked)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CopyResizeButton(count: ticked.count, progress: progress) { make() }
            }
            .navigationTitle("Copy & resize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { task?.cancel(); dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(progress != nil)
        .onDisappear { task?.cancel() }
    }

    private func make() {
        let targets = ticked
        task = Task { @MainActor in
            defer { progress = nil; task = nil }
            guard let made = try? await CopyResize.make(source, targets: targets, progress: { progress = $0 }),
                  !made.isEmpty else { return }
            onDone(made)
            dismiss()
        }
    }
}
