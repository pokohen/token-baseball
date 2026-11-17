import SwiftUI
import TokenBaseballCore

/// 여러 개 중 하나를 고르는 버튼 묶음.
///
/// 고른 것은 강조색으로 채우고 체크 표시를 붙인다. macOS의 기본 버튼은 색조(tint)만 바꿔서는
/// 고른 것과 고르지 않은 것이 거의 똑같이 보여서, 버튼 모양을 직접 그린다.
struct ChoiceGrid<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    var columns = 3
    let label: (Item) -> String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(items, id: \.self) { item in
                let chosen = selection == item
                Button {
                    selection = item
                } label: {
                    HStack(spacing: 3) {
                        if chosen { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                        Text(label(item)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.callout.weight(chosen ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .foregroundStyle(chosen ? Color.white : Color.primary)
                    .background(
                        chosen ? Color.accentColor : Color.secondary.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(item))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}
