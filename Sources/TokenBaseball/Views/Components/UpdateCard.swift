import AppKit
import SwiftUI
import TokenBaseballCore

/// 설정 탭: 지금 버전, 새 버전이 있는지, 업데이트하는 방법.
struct UpdateCard: View {
    @EnvironmentObject var model: AppModel
    @State private var copied = false

    private static let command = "Scripts/update.sh"

    var body: some View {
        Card("업데이트", trailing: UpdateChecker.buildCommit.map { "지금 \(String($0.prefix(7)))" }) {
            if let update = model.update {
                Label("새 버전이 있습니다 (변경 \(update.count)건)", systemImage: "arrow.down.circle.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(Color.accentColor)
                ForEach(update.titles, id: \.self) { title in
                    Text("· \(title)").note().frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("저장소 폴더에서 아래 명령을 실행하면 코드만 새로 받아 앱을 다시 만듭니다. 구단과 선수는 그대로입니다.").note()
                HStack {
                    Text(Self.command).font(.callout.monospaced()).textSelection(.enabled)
                    Spacer()
                    Button(copied ? "복사됨" : "명령 복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.command, forType: .string)
                        copied = true
                    }
                }
            } else if let status = model.updateStatus {
                Text(status).font(.callout)
            } else {
                Text(UpdateChecker.isEnabled ? "아직 확인하지 않았습니다." : "자동 확인이 꺼져 있습니다.").font(.callout)
            }
            HStack {
                Toggle("새 버전 자동 확인", isOn: Binding(
                    get: { UpdateChecker.isEnabled },
                    set: { model.setUpdateCheckEnabled($0) }))
                Spacer()
                Button(model.checkingUpdate ? "확인하는 중…" : "지금 확인") { model.checkForUpdate(manual: true) }
                    .disabled(model.checkingUpdate)
            }
            Text("켜 두면 앱을 켤 때와 여섯 시간마다 GitHub에 새 변경이 있는지만 묻습니다. 보내는 것은 이 앱을 빌드한 버전(커밋)뿐이고, 토큰 사용량과 게임 내용은 보내지 않습니다.").note()
        }
        .font(.callout)
    }
}
