import SwiftUI
import TokenBaseballCore

/// 눈에 띄어야 하는 알림 한 줄. `action`이 있으면 눌러서 이동할 수 있다.
struct Banner: View {
    let text: String
    let color: Color
    var icon = "exclamationmark.triangle.fill"
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
            Text(text).font(.callout)
            Spacer(minLength: 0)
            if action != nil { Image(systemName: "chevron.right") }
        }
        .padding(10)
        .foregroundStyle(.white)
        .background(color, in: RoundedRectangle(cornerRadius: 10))
    }
}
