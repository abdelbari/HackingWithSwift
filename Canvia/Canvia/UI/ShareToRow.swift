// The export sheet's Share to row: the social apps installed on this phone
// (ShareTargets), the design type's own first, five at most, each a tap
// that exports the design in the type that app takes and hands it to it.
// Each is a disc with the app's first letter and its name under it — the
// apps' own marks are theirs — named "Share to Instagram" to VoiceOver.

import SwiftUI
import UIKit

struct ShareToRow: View {
    let targets: [ShareTargets.Target]
    var onShare: (ShareTargets.Target) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(targets) { target in
                    Button { onShare(target) } label: { tile(target) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ShareTargets.shareTo(target))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func tile(_ target: ShareTargets.Target) -> some View {
        VStack(spacing: 4) {
            Text(String(target.name.prefix(1)))
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.accent, in: Circle())
            Text(target.name)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(minWidth: 64)
    }

    /// The targets this phone has, by id: each whose URL scheme an app
    /// answers to (Info.plist's LSApplicationQueriesSchemes lets the app
    /// ask).
    @MainActor
    static func installed() -> Set<String> {
        Set(ShareTargets.all.filter { target in
            target.url.map { UIApplication.shared.canOpenURL($0) } ?? false
        }.map(\.id))
    }
}
