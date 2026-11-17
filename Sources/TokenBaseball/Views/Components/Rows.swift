import SwiftUI
import TokenBaseballCore

/// 표의 한 줄: 왼쪽 이름, 오른쪽 값.
struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(valueColor)
        }
        .font(.callout)
    }
}

struct Stars: View {
    let count: Int

    var body: some View {
        Text(String(repeating: "★", count: count) + String(repeating: "☆", count: 5 - count))
            .font(.caption2)
            .foregroundStyle(Theme.warn)
    }
}

extension View {
    /// 작은 보조 글씨.
    func note() -> some View { font(.caption).foregroundStyle(.secondary) }
}

/// 포지션 약자 (SP, SS, GK …). 목록에서 줄을 맞추려고 폭을 고정한다.
struct PositionTag: View {
    let position: Position

    var body: some View {
        Text(position.rawValue).font(.caption.monospaced()).frame(width: 26, alignment: .leading)
    }
}
