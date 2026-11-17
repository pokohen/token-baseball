import SwiftUI
import TokenBaseballCore

/// 여러 개 중 하나를 고르는 버튼 묶음. 고른 것은 강조색으로 보인다.
struct ChoiceGrid<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    var columns = 3
    let label: (Item) -> String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columns), spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button(label(item)) { selection = item }
                    .buttonStyle(.bordered)
                    .tint(selection == item ? Color.accentColor : .secondary)
            }
        }
    }
}
