import SwiftUI

/// The tester's splash: what Gymship does, and the flows worth trying.
/// Shown once after onboarding, and reachable any time from You.
struct WhatToTestView: View {
    @Environment(ThemeManager.self) private var theme

    let onDone: () -> Void

    @State private var appeared = false

    private var shareText: String {
        String(localized: "I'm testing Gymship — it finds the free time your crew shares and turns it into a workout. Join me on TestFlight: \(shareLink)")
    }
    private let shareLink = "https://testflight.apple.com/join/"

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(WhatToTest.steps.enumerated()), id: \.element.id) { index, step in
                            row(step, shift: Double(index) * 0.05)
                                .gymshipAppear(appeared, delay: Double(index) * 0.03)
                        }
                    }

                    Label(WhatToTest.feedbackNote, systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .glassCard(cornerRadius: 18)
                        .gymshipAppear(appeared, delay: Double(WhatToTest.steps.count) * 0.03)
                }
                .padding(.horizontal, 28)
                .padding(.top, 64)
                .padding(.bottom, 150)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .scrollIndicators(.hidden)

            VStack(spacing: 10) {
                ShareLink(item: shareText) {
                    Label("Invite a friend to test", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())

                Button("Continue", action: onDone)
                    .buttonStyle(GymshipButtonStyle())
            }
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
            Text("WHAT TO TEST")
                .font(.system(.footnote, weight: .semibold))
                .tracking(2)
                .foregroundStyle(theme.accent)

            Text("Try Gymship\nwith your crew")
                .font(.display(36))
                .fixedSize(horizontal: false, vertical: true)

            Text(WhatToTest.intro)
                .font(.system(.title3))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .gymshipAppear(appeared, from: 12)
    }

    private func row(_ step: WhatToTest.Step, shift: Double) -> some View {
        HStack(alignment: .top, spacing: 16) {
            GlyphBadge(symbol: step.symbol, size: 48, shift: shift)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.display(.headline))
                Text(step.detail)
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
