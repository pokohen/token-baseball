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
