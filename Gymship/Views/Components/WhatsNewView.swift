import SwiftUI

/// The "What's new" splash: one section per release you haven't seen, newest
/// first, with a single Continue button pinned at the bottom.
struct WhatsNewView: View {
    @Environment(ThemeManager.self) private var theme

    let releases: [ReleaseNotes.Release]
    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    header

                    ForEach(Array(releases.enumerated()), id: \.element.id) { releaseIndex, release in
                        VStack(alignment: .leading, spacing: 18) {
                            if releases.count > 1 {
                                SectionHeader(title: release.versionLabel, subtitle: release.headline)
                            }
                            ForEach(Array(release.items.enumerated()), id: \.element.id) { itemIndex, item in
                                row(item, shift: Double(itemIndex) * 0.05)
                                    .gymshipAppear(appeared, delay: Double(releaseIndex * 4 + itemIndex) * 0.03)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 64)
                .padding(.bottom, 130)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .scrollIndicators(.hidden)

            Button("Continue", action: onDone)
                .buttonStyle(GymshipButtonStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
        .presentationBackground {
            GymshipBackground(allowsMotion: false)
        }
        .onAppear { appeared = true }
        .sensoryFeedback(.success, trigger: appeared)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT'S NEW")
                .font(.system(.footnote, weight: .semibold))
                .tracking(2)
                .foregroundStyle(theme.accent)

            Text(releases.count == 1 ? (releases.first?.headline ?? String(localized: "What's new")) : String(localized: "Since your last update"))
                .font(.display(36))
                .fixedSize(horizontal: false, vertical: true)

            if let latest = releases.first {
                Text("Version \(latest.versionLabel)")
                    .font(.system(.subheadline, weight: .semibold))
                    .glassPill(isActive: false)
            }
        }
        .gymshipAppear(appeared, from: 12)
    }

    private func row(_ item: ReleaseNotes.Item, shift: Double) -> some View {
        HStack(alignment: .top, spacing: 16) {
            GlyphBadge(symbol: item.symbol, size: 48, shift: shift)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.display(.headline))
                    Text(item.kind.label.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(item.kind == .fixed ? Color.orange : theme.accent)
                }
                Text(item.detail)
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
