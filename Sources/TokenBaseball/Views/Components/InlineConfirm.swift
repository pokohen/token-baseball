import SwiftUI

/// 되돌릴 수 없는 일을 하기 전에 그 자리에서 한 번 더 묻는 줄.
///
/// 상단바 팝오버에서는 시스템 확인 창(`confirmationDialog`)이 뜨지 않아 버튼이 눌리지 않는 것처럼 보인다.
/// 그래서 창을 띄우지 않고 카드 안에 묻는 줄을 펼친다.
struct InlineConfirm: View {
    let message: String
    let confirmTitle: String
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("취소", action: cancel).keyboardShortcut(.cancelAction)
                Button(confirmTitle, role: .destructive, action: confirm)
                    .buttonStyle(.borderedProminent).tint(Theme.loss)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.loss.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
