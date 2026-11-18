import AppKit
import SwiftUI
import TokenBaseballCore

/// 설정 탭: 지금 모드만, 또는 전부 처음부터 다시 시작한다. 저장 파일은 backups 폴더로 옮겨 둔다.
struct ResetCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var confirmReset = false
    @State private var confirmResetAll = false

    var body: some View {
        Card("초기화") {
            HStack {
                Button("\(model.slot.label) 처음부터 다시") { confirmReset = true }
                    .confirmationDialog(
                        "지금 하던 \(model.slot.label)\(game.isCareer ? "를" : "을") 그만두고 처음부터 다시 시작할까요?",
                        isPresented: $confirmReset, titleVisibility: .visible
                    ) {
                        Button("처음부터 다시", role: .destructive) { model.reset(all: false) }
                    } message: {
                        Text("다른 모드는 그대로입니다. 저장 파일은 지우지 않고 backups 폴더로 옮겨 둡니다.")
                    }
                Button("전체 초기화") { confirmResetAll = true }
                    .confirmationDialog(
                        "모든 모드를 처음부터 다시 시작할까요?",
                        isPresented: $confirmResetAll, titleVisibility: .visible
                    ) {
                        Button("전체 초기화", role: .destructive) { model.reset(all: true) }
                    } message: {
                        Text("만들어 둔 선수와 구단이 모두 사라집니다. 저장 파일은 지우지 않고 backups 폴더로 옮겨 둡니다.")
                    }
            }
            Text("초기화한 뒤에는 처음 화면에서 새로 만듭니다. 예전 것은 저장 폴더의 backups 안에 날짜별로 남아 있어, 파일을 원래 자리로 옮기면 되살릴 수 있습니다.").note()
            Button("저장 폴더 열기") {
                NSWorkspace.shared.open(model.baseStore.fileURL.deletingLastPathComponent())
            }
        }
        .font(.callout)
    }
}
