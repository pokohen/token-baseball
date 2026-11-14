import SwiftUI
import TokenBaseballCore

enum Theme {
    static let popoverWidth: CGFloat = 420
    static let popoverHeight: CGFloat = 600

    static let teamColors: [Color] = [
        Color(red: 0.16, green: 0.42, blue: 0.80), Color(red: 0.78, green: 0.22, blue: 0.22),
        Color(red: 0.13, green: 0.55, blue: 0.38), Color(red: 0.85, green: 0.52, blue: 0.10),
        Color(red: 0.45, green: 0.30, blue: 0.72), Color(red: 0.10, green: 0.55, blue: 0.62),
        Color(red: 0.72, green: 0.28, blue: 0.52), Color(red: 0.35, green: 0.38, blue: 0.45),
    ]
    static let teamColorNames = ["파랑", "빨강", "초록", "주황", "보라", "청록", "자주", "회색"]
    static let emblems = ["shield.fill", "star.fill", "flame.fill", "bolt.fill", "leaf.fill", "crown.fill"]
    static let emblemNames = ["방패", "별", "불꽃", "번개", "잎", "왕관"]

    static func color(_ team: Team) -> Color { teamColors[team.colorIndex % teamColors.count] }
    static func emblem(_ team: Team) -> String { emblems[team.emblemIndex % emblems.count] }

    static let win = Color(red: 0.13, green: 0.55, blue: 0.38)
    static let loss = Color(red: 0.78, green: 0.22, blue: 0.22)
    static let warn = Color(red: 0.85, green: 0.52, blue: 0.10)
}

/// 내용을 묶는 카드.
struct Card<Content: View>: View {
    var title: String?
    var trailing: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let trailing {
                        Text(trailing).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct EmblemView: View {
    let team: Team
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Theme.color(team))
            Image(systemName: Theme.emblem(team))
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

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
