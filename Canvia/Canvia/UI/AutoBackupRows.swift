// Settings ▸ Backup's "Back up automatically" (AutoBackups): on, it asks for
// a folder first; then how often — Daily or Weekly — and how many to keep,
// when the last one was and how big, Back up now, Choose folder, and why the
// last one could not run, when it could not. As the Android twin's
// AutoBackupRows. And Home's line when one could not run.

import SwiftUI
import UniformTypeIdentifiers

struct AutoBackupRows: View {
    private var backups: AutoBackups { AutoBackups.shared }
    /// The Files picker, for a folder.
    @State private var choosing = false

    var body: some View {
        Group {
            Toggle(isOn: Binding(get: { backups.config.on }, set: { on in
                // Turned on, it asks for the folder first; it is on once one
                // is chosen.
                if on { choosing = true } else { backups.turnOff() }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Back up automatically")
                    Text("A backup into a folder you choose, daily or weekly, whenever something has changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if backups.config.on { details }
        }
        // Its own picker, apart from Restore's, so each opens.
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result { backups.chose(folder) }
        }
    }

    @ViewBuilder
    private var details: some View {
        Picker(selection: every) {
            Text("Daily").tag(AutoBackup.daily)
            Text("Weekly").tag(AutoBackup.weekly)
        } label: {
            Text("Back up automatically")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        Picker("Copies to keep", selection: keep) {
            ForEach(AutoBackup.keepChoices, id: \.self) { Text(verbatim: "\($0)").tag($0) }
        }
        Text(lastText)
            .font(.footnote)
            .foregroundStyle(.secondary)
        if backups.config.lastError != nil {
            Label(AutoBackup.failed, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
        Button(backups.running ? tr("Backing up") : tr("Back up now")) {
            Task { await backups.runIfDue(force: true) }
        }
        .disabled(backups.running)
        Button("Choose folder") { choosing = true }
    }

    private var every: Binding<String> {
        Binding(get: { backups.config.every }, set: { next in backups.update { $0.every = next } })
    }

    private var keep: Binding<Int> {
        Binding(get: { backups.config.keep }, set: { next in backups.update { $0.keep = next } })
    }

    /// "Last backed up 2 days ago · 184 MB", or that none has been yet.
    private var lastText: String {
        let config = backups.config
        guard config.lastAt > 0 else { return tr("Not backed up yet") }
        let ago = RelativeTime.lowercasedFirst(RelativeTime.text(ms: Double(config.lastAt)))
        return AutoBackup.lastNote(ago: ago, size: StorageReport.text(config.lastBytes))
    }
}

/// Home's line when an automatic backup could not run — the folder gone, or
/// Canvia's access to it taken back — until the folder is chosen again in
/// Settings, which a tap opens.
struct AutoBackupBanner: View {
    var onOpen: () -> Void
    private var backups: AutoBackups { AutoBackups.shared }

    var body: some View {
        if backups.config.on && backups.config.lastError != nil {
            Button(action: onOpen) {
                Label(AutoBackup.failed, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }
}
