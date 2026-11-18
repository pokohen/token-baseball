import SwiftUI
import TokenBaseballCore

/// 내용을 묶는 카드.
struct Card<Content: View>: View {
    var title: String?
    var trailing: String?
    /// 제목 줄 오른쪽에 글자 대신 놓을 그림 (예: 남은 경기 기회).
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(
        _ title: String? = nil, trailing: String? = nil, accessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.accessory = accessory
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
                    if let accessory { accessory }
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
