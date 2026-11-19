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

    // MARK: 用户选择（取值受设备能力约束）

    /// 模式序号，1 基，与固件 mode 参数一致
    @Published var selectedModeIndex: Int = 1
    /// 亮度档，0 基（0=50% 1=70% 2=90%）
    @Published var brightLevel: Int = 0
    /// 时长档，1 基，对应设备上报的时长表
    @Published var durationLevel: Int = 1

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

        // 设备版本一变（连上另一台机器）就把选择收进新设备的合法范围
        bluetooth.$deviceInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in self?.adoptDeviceLimits(info) }
            .store(in: &cancellables)

        bluetooth.$lastAck
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ack in
                guard let self = self, !ack.isOK else { return }
                self.notice = "设备未执行：\(ack.reason)"
                if self.isRunning { self.finish(completed: false) }
            }
            .store(in: &cancellables)
    }

    // MARK: 派生显示

    var durationMinutes: Int {
        let list = bluetooth.durations
        guard list.indices.contains(durationLevel - 1) else { return 0 }
        return list[durationLevel - 1]
    }

    var progress: Double {
        let total = Double(max(1, durationMinutes) * 60)
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

    var brightText: String {
        let percents = BLEConfig.brightPercents
        return percents.indices.contains(brightLevel) ? "\(percents[brightLevel])%" : "第 \(brightLevel + 1) 档"
    }

    // MARK: 对齐设备能力

    /// 以设备为准：模式数、亮度档数、时长表都按 INFO 上报裁剪
    private func adoptDeviceLimits(_ info: BLEConfig.DeviceInfo?) {
        guard let info = info else { return }
        let modeCount = max(1, info.modeChannels.count)
        if selectedModeIndex > modeCount { selectedModeIndex = modeCount }
        if selectedModeIndex < 1 { selectedModeIndex = 1 }

        let brightLimit = max(1, info.brightCount)
        if brightLevel >= brightLimit { brightLevel = brightLimit - 1 }
        if brightLevel < 0 { brightLevel = 0 }

        let timeCount = max(1, info.durations.count)
        if durationLevel > timeCount { durationLevel = timeCount }
        if durationLevel < 1 { durationLevel = 1 }

        notice = nil
    }

    // MARK: 护理控制

    func start() {
        guard bluetooth.connected != nil else {
            notice = "请先在「设备」页连接电子面膜"
            return
        }
        guard bluetooth.deviceInfo != nil else {
            notice = "还在识别设备版本，请稍候再开始"
            return
        }
        guard !isRunning else { return }

        // 一条 SET_ALL 下发，设备侧顺序执行：亮度 → 定时 → 启动
        bluetooth.startTherapy(
            mode: selectedModeIndex,
            bright: brightLevel,
            timeLevel: durationLevel
        )

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
            modeTitle: bluetooth.modeTitle(selectedModeIndex),
            intensity: brightLevel + 1,
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
    /// 设备到点会自动关机，此时会先收到一帧 running=0，再断连。
    private func applyDeviceStatus(_ status: BLEConfig.DeviceStatus) {
        // 设备被按键改了模式/亮度/时长，界面跟着走（以设备为准）
        if !isRunning {
            if status.mode >= 1, status.mode != selectedModeIndex,
               status.mode <= max(1, bluetooth.modeCount) {
                selectedModeIndex = status.mode
            }
            if status.bright != brightLevel, status.bright < max(1, bluetooth.brightCount) {
                brightLevel = status.bright
            }
        }

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

    /// 用户在设置里改动参数后，立即同步到设备（待机态：只记档位，不点灯）
    func syncSettings() {
        guard bluetooth.connected != nil, !isRunning else { return }
        bluetooth.applyMode(selectedModeIndex)
        bluetooth.applyBright(brightLevel)
        bluetooth.applyTime(durationLevel)
    }

    /// 模式：待机时只记档位；理疗中立即切换，设备会"嘀"一声并点亮档位灯 10 秒。
    /// 设备端切换模式不改倒计时，这里也不动本地 remain，两边保持同步。
    func setModeIndex(_ index: Int) {
        guard index != selectedModeIndex else { return }
        selectedModeIndex = index
        guard bluetooth.connected != nil else { return }
        bluetooth.applyMode(index)
    }

    /// 亮度档：待机时同步给设备（下次开始用），理疗中立即生效。
    /// 设备端收到后会"嘀"一声，并把定时/亮度指示灯按新档位点亮 10 秒。
    func setBrightLevel(_ level: Int) {
        brightLevel = level
        guard bluetooth.connected != nil else { return }
        bluetooth.applyBright(level)
    }

    /// 时长档：待机时同步给设备，理疗中立即改变，设备会按新时长重新计时。
    /// 本地倒计时也跟着重置，否则和设备的 remain_sec 会对不上。
    func setDurationLevel(_ level: Int) {
        durationLevel = level
        guard bluetooth.connected != nil else { return }
        bluetooth.applyTime(level)
        if isRunning {
            startedAt = Date()
            remainingSeconds = durationMinutes * 60
        }
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
