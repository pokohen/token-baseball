import SwiftUI
import TokenBaseballCore

/// 내 선수를 만들 때 정하는 값을 고르는 화면 조각. 첫 시작과 은퇴 뒤 새 선수 만들기에 같이 쓴다.
struct CareerForm: View {
    @Binding var setup: CareerSetup
    var sport: Sport = .baseball
    @State private var pitcher = false

    var body: some View {
        if sport == .football { football } else { baseball }
    }

    private var football: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("선수 이름", text: $setup.name).textFieldStyle(.roundedBorder)
            ChoiceGrid(items: CareerSetup.footballPositions, selection: $setup.position, columns: 4) { $0.label }
            Text(positionNote).note()
            Picker("출신", selection: $setup.hometown) {
                ForEach(NameGenerator.userCities, id: \.self) { Text($0).tag($0) }
            }
        }
        .font(.callout)
        .onAppear { if setup.position.sport != .football { setup.position = .forward } }
    }

    private var baseball: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("선수 이름", text: $setup.name).textFieldStyle(.roundedBorder)

            Picker("유형", selection: Binding(
                get: { pitcher },
                set: { value in
                    pitcher = value
                    setup.position = value ? .starter : .shortstop
                })) {
                Text("타자").tag(false)
                Text("투수").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let positions = pitcher ? CareerSetup.pitcherPositions : CareerSetup.batterPositions
            ChoiceGrid(items: positions, selection: $setup.position, columns: pitcher ? 2 : 3) { $0.label }
            Text(positionNote).note()

            HStack {
                Picker("타석", selection: $setup.bats) {
                    Text("우타").tag(Hand.right)
                    Text("좌타").tag(Hand.left)
                }
                Picker("투구", selection: $setup.throwsHand) {
                    Text("우투").tag(Hand.right)
                    Text("좌투").tag(Hand.left)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("출신", selection: $setup.hometown) {
                ForEach(NameGenerator.userCities, id: \.self) { Text($0).tag($0) }
            }
        }
        .font(.callout)
        .onAppear {
            if setup.position.sport != .baseball { setup.position = .shortstop }
            pitcher = setup.position.isPitcher
        }
    }

    private var positionNote: String {
        switch setup.position {
        case .starter:
            "선발 투수: 쉬는 날을 채우면 반드시 선발로 나옵니다 (시민 리그는 3경기에 한 번, 3부부터는 5경기에 한 번). 나오지 않는 날은 팀 경기를 지켜보고, 대신 훈련을 한 번 더 합니다."
        case .reliever:
            "불펜 투수: 선발이 내려가면 가장 먼저 올라옵니다. 자주 나오지만 짧게 던지고, 많이 던졌거나 연투한 다음 날은 쉽니다."
        case .goalkeeper:
            "골키퍼: 교체로 나올 수 없어서, 주전을 따내기 전에는 친선 경기와 네 경기 중 한 경기에만 나옵니다. 주전까지 가장 오래 걸리는 포지션입니다. 골키핑이 능력의 70%입니다."
        case .defender:
            "수비수: 수비·피지컬·스피드가 중요합니다. 무실점 경기와 공을 뺏는 장면으로 평점을 받습니다."
        case .midfielder:
            "미드필더: 패스·드리블이 중요합니다. 공을 앞으로 운반하고 도움을 올립니다."
        case .forward:
            "공격수: 슈팅·드리블·스피드가 중요합니다. 골로 평가받습니다. 주전이 아니면 벤치에서 시작해 후반에 교체로 들어갑니다."
        case .designated:
            "지명타자: 매 경기 타석에 서고 수비는 하지 않습니다. 컨택·파워·선구안·주력만 훈련합니다."
        default:
            "타자: 매 경기 선발로 나옵니다. 포지션은 커리어 중에 바꿀 수 없습니다."
        }
    }
}
