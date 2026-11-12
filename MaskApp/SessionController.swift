import Foundation
import Combine

struct SessionRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var modeTitle: String
    var intensity: Int
    var plannedMinutes: Int
    var actualSeconds: Int
    var completed: Bool
}

final class SessionController: ObservableObject {

    @Published var selectedMode: BLEConfig.Mode = .led
    @Published var intensity: Int = 3
    @Published var durationMinutes: Int = 15

    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isRunning = false
    @Published private(set) var records: [SessionRecord] = []
    @Published var notice: String?

    private let bluetooth: BluetoothManager
    private var timer: Timer?
    private var startedAt: Date?
    private var cancellables = Set<AnyCancellable>()
    private static let storeKey = "maskapp.records"

    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        loadRecords()
        bluetooth.$status
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.applyDeviceStatus(status) }
            .store(in: &cancellables)
    }

    // MARK: 派生显示

    var progress: Double {
        let total = Double(durationMinutes * 60)
        guard total > 0 else { return 0 }
        return min(1.0, max(0.0, 1.0 - Double(remainingSeconds) / total))
    }

    var remainingText: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var totalSessions: Int { records.count }

    var totalMinutes: Int {
        records.reduce(0) { $0 + $1.actualSeconds } / 60
    }

    // MARK: 护理控制

    func start() {
        guard bluetooth.connected != nil else {
            notice = "请先在「设备」页连接电子面膜"
            return
        }
        guard !isRunning else { return }

        // 顺序与固件保持一致：模式 → 档位 → 时长 → 启动
        bluetooth.applyMode(selectedMode)
        bluetooth.applyIntensity(intensity)
        bluetooth.applyDuration(durationMinutes)
        bluetooth.startTreatment()

        remainingSeconds = durationMinutes * 60
        startedAt = Date()
        isRunning = true
        notice = nil

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.remainingSeconds > 0 { self.remainingSeconds -= 1 }
            if self.remainingSeconds <= 0 { self.finish(completed: true) }
        }
    }

    func finish(completed: Bool) {
        guard isRunning else { return }
        isRunning = false              // 先置位，避免设备状态回调造成重入
        timer?.invalidate()
        timer = nil

        bluetooth.stopTreatment()

        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt ?? Date())))
        let record = SessionRecord(
            id: UUID(),
            date: Date(),
            modeTitle: selectedMode.title,
            intensity: intensity,
            plannedMinutes: durationMinutes,
            actualSeconds: elapsed,
            completed: completed
        )
        records.insert(record, at: 0)
        saveRecords()

        remainingSeconds = 0
        startedAt = nil
        notice = completed ? "本次护理已完成" : "本次护理已提前结束"
    }

    /// 设备端主动停止时，本地随之收尾；设备上报的剩余时间也作为校准来源。
    private func applyDeviceStatus(_ status: BLEConfig.DeviceStatus) {
        guard isRunning else { return }
        if !status.isRunning {
            finish(completed: false)
            return
        }
        if status.remainingSeconds > 0,
           abs(status.remainingSeconds - remainingSeconds) > 2 {
            remainingSeconds = status.remainingSeconds
        }
    }

    /// 用户在设置里改动参数后，立即同步到设备
    func syncSettings() {
        guard bluetooth.connected != nil, !isRunning else { return }
        bluetooth.applyMode(selectedMode)
        bluetooth.applyIntensity(intensity)
        bluetooth.applyDuration(durationMinutes)
    }

    // MARK: 记录持久化

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: Self.storeKey),
              let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) else { return }
        records = decoded
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.storeKey)
    }

    func clearRecords() {
        records.removeAll()
        saveRecords()
    }
}
