import SwiftUI

/// One calendar with a single switch: does it count as busy time?
struct CalendarRow: View {
    let calendar: GymCalendar
    let availability: CalendarAvailability
    let onChange: (CalendarAvailability) -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { availability == .unavailable },
            set: { onChange($0 ? .unavailable : .available) }
        )) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: calendar.colorHex))
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.title)
                        .font(.system(.body, weight: .medium))
                    Text(calendar.sourceTitle)
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .adaptiveToggle()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
