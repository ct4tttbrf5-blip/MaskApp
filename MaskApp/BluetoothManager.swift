import Foundation
import CoreBluetooth
import Combine

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let isDemo: Bool

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.rssi == rhs.rssi && lhs.isDemo == rhs.isDemo
    }
}

final class BluetoothManager: NSObject, ObservableObject,
                              CBCentralManagerDelegate, CBPeripheralDelegate {

    // MARK: 界面状态

    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var connected: DiscoveredDevice?
    @Published private(set) var status: BLEConfig.DeviceStatus?
    /// 设备版本与能力，连上后由固件 INFO 帧决定；nil 表示还没识别出来
    @Published private(set) var deviceInfo: BLEConfig.DeviceInfo?
    @Published private(set) var lastAck: BLEConfig.Ack?
    @Published private(set) var isScanning = false
    @Published private(set) var logs: [String] = []

    /// 演示模式：不依赖真实硬件，用模拟设备跑通全流程。在「设置」里开关。
    @Published var demoMode: Bool {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: Self.demoKey)
            log(demoMode ? "已切换到演示模式" : "已切换到真机模式")
            resetConnection()
        }
    }

    /// 演示时假装连的是哪一版，方便没有激光样机时先看界面
    @Published var demoDeviceType: BLEConfig.DeviceType {
        didSet {
            UserDefaults.standard.set(Int(demoDeviceType.rawValue), forKey: Self.demoTypeKey)
            guard demoMode, connected != nil else { return }
            deviceInfo = BLEConfig.demoInfo(type: demoDeviceType)
            demoModeIndex = 1
            log("演示设备切换为 \(demoDeviceType.title)")
            publishDemoStatus()
        }
    }

    /// 协议未确定时默认显示周边全部 BLE 设备，方便先找到设备名和 UUID。
    @Published var showAllDevices: Bool = true

    private static let demoKey = "maskapp.demoMode"
    private static let demoTypeKey = "maskapp.demoDeviceType"

    // MARK: 私有状态

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var reconnectID: UUID?

    /// 收包缓冲：粘包/半包都在这里拼
    private var rxBuffer = Data()
    private var infoRetryCount = 0

    /// 蓝牙还没就绪时点了扫描：等 poweredOn 回调里补扫，避免"点了没反应"
    private var pendingScan = false
    /// 连接尝试次数，用于失败后自动重试一次（JL 方案刚开广播时第一次常失败）
    private var connectAttempts = 0
    /// 每次连接一个令牌，防止过期的超时回调把新连接取消掉
    private var connectToken = UUID()
    /// 服务发现失败后重连过一次就不再重试，避免死循环
    private var serviceRetryUsed = false

    private var demoTimer: Timer?
    private var demoRemaining = 0
    private var demoRunning = false
    private var demoModeIndex = 1
    private var demoBright = 0

    override init() {
        demoMode = UserDefaults.standard.bool(forKey: Self.demoKey)
        let storedType = UserDefaults.standard.integer(forKey: Self.demoTypeKey)
        demoDeviceType = BLEConfig.DeviceType(rawValue: UInt8(storedType)) ?? .led
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: 便利取值

    /// 当前设备的模式列表（未识别版本时为空）
    var modes: [BLEConfig.TherapyMode] { deviceInfo?.modes ?? [] }

    var modeCount: Int { deviceInfo?.modeChannels.count ?? 0 }

    var durations: [Int] { deviceInfo?.durations ?? [] }

    var brightCount: Int { deviceInfo?.brightCount ?? 0 }

    func modeTitle(_ index: Int) -> String {
        modes.first(where: { $0.id == index })?.title ?? "模式 \(index)"
    }

    /// 设备识别是否完成（决定控制页能不能点）
    var isDeviceReady: Bool { connected != nil && deviceInfo != nil }

    // MARK: 扫描

    func startScan() {
        if isScanning { return }
        if demoMode {
            startDemoScan()
            return
        }
        guard central.state == .poweredOn else {
            pendingScan = true
            log("蓝牙未就绪（\(stateText(central.state))），就绪后自动开始扫描")
            return
        }
        pendingScan = false
        devices.removeAll()
        isScanning = true
        central.scanForPeripherals(
            withServices: BLEConfig.scanServices,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        log("开始扫描（面膜需长按电源键 2 秒开机后才会广播）")

        // 扫 12 秒一台都没看到，给一句可执行的提示，省得盯着空列表猜
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self = self, self.isScanning, self.devices.isEmpty else { return }
            self.log("扫描 12 秒未发现任何设备：①面膜是否长按开机 ②手机设置→隐私与安全性→蓝牙 是否允许本 App ③把面膜靠近手机再试")
        }
    }

    func stopScan() {
        if !demoMode, central.state == .poweredOn { central.stopScan() }
        isScanning = false
    }

    private func startDemoScan() {
        let suffix = demoDeviceType == .led ? "LED 版（演示）" : "激光版（演示）"
        devices = [
            DiscoveredDevice(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "V3.0-Mask \(suffix)",
                rssi: -52,
                isDemo: true
            ),
            DiscoveredDevice(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                name: "V3.0-Mask-2（演示）",
                rssi: -74,
                isDemo: true
            )
        ]
        isScanning = true
        log("演示模式：已生成 2 台模拟设备")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.isScanning = false
        }
    }

    // MARK: 连接

    func connect(_ device: DiscoveredDevice) {
        stopScan()
        if demoMode {
            connected = device
            status = nil
            deviceInfo = BLEConfig.demoInfo(type: demoDeviceType)
            demoRemaining = 0
            demoRunning = false
            demoModeIndex = 1
            demoBright = 0
            log("已连接 \(device.name)，识别为 \(demoDeviceType.title)")
            startDemoLoop()
            publishDemoStatus()
            return
        }
        guard peripherals[device.id] != nil, central.state == .poweredOn else {
            log("连接失败：找不到设备或蓝牙未就绪")
            return
        }
        connectAttempts = 0
        serviceRetryUsed = false
        reconnectID = device.id
        startConnect(device.id)
    }

    /// 真正发起连接 + 超时保护。
    /// iOS 的 connect 没有超时参数，设备不在广播范围时会一直挂着，
    /// 界面上就表现为"点了一直转圈、也不报错"。
    private func startConnect(_ id: UUID) {
        guard let target = peripherals[id], central.state == .poweredOn else { return }
        connectAttempts += 1
        let token = UUID()
        connectToken = token
        target.delegate = self
        log("正在连接…（第 \(connectAttempts) 次）")
        central.connect(target, options: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self = self,
                  self.connectToken == token,
                  self.peripheral?.state != .connected else { return }
            self.log("连接超时：设备没有响应，请确认面膜处于开机状态且离手机 1 米内")
            if let p = self.peripherals[id] { self.central.cancelPeripheralConnection(p) }
        }
    }

    func disconnect() {
        reconnectID = nil
        if let p = peripheral, central.state == .poweredOn {
            central.cancelPeripheralConnection(p)
        }
        resetConnection()
        log("已断开连接")
    }

    private func resetConnection() {
        demoTimer?.invalidate()
        demoTimer = nil
        stopScan()
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connected = nil
        status = nil
        deviceInfo = nil
        lastAck = nil
        rxBuffer.removeAll()
        infoRetryCount = 0
        devices.removeAll()
    }

    // MARK: 指令下发

    func applyMode(_ index: Int) {
        send(BLEConfig.setMode(index), label: "设置\(modeTitle(index))")
    }

    func applyBright(_ level: Int) {
        let percent = BLEConfig.brightPercents.indices.contains(level)
            ? "\(BLEConfig.brightPercents[level])%"
            : "第 \(level + 1) 档"
        send(BLEConfig.setBright(level), label: "设置亮度 \(percent)")
    }

    /// level 从 1 开始，对应设备上报的时长表下标
    func applyTime(_ level: Int) {
        let minutes = durations.indices.contains(level - 1) ? "\(durations[level - 1]) 分钟" : "第 \(level) 档"
        send(BLEConfig.setTime(level), label: "设置时长 \(minutes)")
    }

    /// 一次设全并启动：模式 / 亮度 / 定时
    func startTherapy(mode: Int, bright: Int, timeLevel: Int) {
        send(
            BLEConfig.setAll(mode: mode, bright: bright, timeLevel: timeLevel),
            label: "开始护理（模式 \(mode) / 亮度 \(bright + 1) / 时长档 \(timeLevel)）"
        )
    }

    func stopTreatment() {
        send(BLEConfig.stop(), label: "停止护理")
    }

    func requestStatus() {
        send(BLEConfig.queryStatus(), label: "查询状态")
    }

    func requestInfo() {
        send(BLEConfig.queryInfo(), label: "查询设备版本")
    }

    /// 连上后主动握手：拿不到 INFO 就重试 3 次，然后提示用户
    func beginHandshake() {
        guard !demoMode else { return }
        infoRetryCount = 0
        requestInfoWithRetry()
    }

    private func requestInfoWithRetry() {
        guard !demoMode, peripheral != nil, deviceInfo == nil else { return }
        guard infoRetryCount < 3 else {
            log("设备未回应版本查询，请确认固件已烧入 BLE 协议（v197 及以上）")
            return
        }
        infoRetryCount += 1
        requestInfo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self = self else { return }
            if self.deviceInfo == nil, self.peripheral != nil {
                self.requestInfoWithRetry()
            }
        }
    }

    func send(_ data: Data, label: String) {
        log("→ \(label)  \(hex(data))")
        if demoMode {
            handleDemoCommand(data)
            return
        }
        guard let p = peripheral, let c = writeCharacteristic else {
            log("指令未发送：设备未连接或未发现写特征")
            return
        }
        var offset = 0
        while offset < data.count {
            let end = min(offset + BLEConfig.maxPacketSize, data.count)
            p.writeValue(data.subdata(in: offset..<end), for: c, type: BLEConfig.writeType)
            offset = end
        }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        log("蓝牙状态：\(stateText(central.state))")

        if central.state == .poweredOn, pendingScan, !demoMode {
            pendingScan = false
            startScan()
            return
        }
        if central.state == .poweredOn,
           !demoMode,
           let id = reconnectID,
           let target = peripherals[id] {
            log("尝试自动重连…")
            central.connect(target, options: nil)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "未知设备"

        if !showAllDevices, !name.hasPrefix(BLEConfig.advertisedNamePrefix) { return }
        guard RSSI.intValue >= BLEConfig.minRSSI else { return }

        peripherals[peripheral.identifier] = peripheral
        let device = DiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            isDemo: false
        )
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
            log("发现设备 \(name)  RSSI \(RSSI.intValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.peripheral = peripheral
        connectAttempts = 0
        connected = devices.first(where: { $0.id == peripheral.identifier })
            ?? DiscoveredDevice(
                id: peripheral.identifier,
                name: peripheral.name ?? BLEConfig.advertisedNamePrefix,
                rssi: 0,
                isDemo: false
            )
        deviceInfo = nil
        rxBuffer.removeAll()
        log("已连接 \(connected?.name ?? "设备")，正在读取设备版本…")
        peripheral.discoverServices([BLEConfig.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        log("连接失败：\(error?.localizedDescription ?? "未知原因")")
        // 刚开广播时第一次连接经常失败，自动再试一次，省得用户来回点
        if connectAttempts < 2, let id = reconnectID, central.state == .poweredOn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.startConnect(id)
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        log("连接断开：\(error?.localizedDescription ?? "主动断开")")
        connected = nil
        status = nil
        deviceInfo = nil
        if let id = reconnectID, let target = peripherals[id], central.state == .poweredOn {
            log("尝试自动重连…")
            central.connect(target, options: nil)
        }
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error { log("服务发现失败：\(error.localizedDescription)") }
        let services = peripheral.services ?? []
        if services.isEmpty {
            /*
             * iOS 会按外设缓存 GATT。换过固件之后有时会读到旧缓存，
             * 表现就是"连上了但找不到 0xFFE0"。这里断开重连一次，
             * iOS 会重新做服务发现；只重试一次，避免死循环。
             */
            if !serviceRetryUsed, reconnectID != nil, central.state == .poweredOn {
                serviceRetryUsed = true
                log("未发现 0xFFE0 服务，断开重连一次以刷新 iOS 的 GATT 缓存…")
                central.cancelPeripheralConnection(peripheral)
                return
            }
            log("未发现 0xFFE0 服务：请确认烧的是带 BLE 协议的固件（v197 及以上）")
            return
        }
        for service in services {
            log("服务 \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error { log("特征发现失败：\(error.localizedDescription)") }
        for characteristic in service.characteristics ?? [] {
            let props = characteristic.properties
            log("  特征 \(characteristic.uuid.uuidString)  属性 \(props.rawValue)")

            if characteristic.uuid == BLEConfig.writeUUID {
                writeCharacteristic = characteristic
                log("  → 已匹配写特征 0xFFE1")
            }
            if characteristic.uuid == BLEConfig.notifyUUID {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                log("  → 已匹配通知特征 0xFFE2")
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            log("订阅通知失败：\(error.localizedDescription)")
            return
        }
        log("已订阅 \(characteristic.uuid.uuidString) 通知")
        // 通道打通了，立刻握手识别是 LED 版还是激光版
        beginHandshake()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error { log("读取失败：\(error.localizedDescription)") }
        let data = characteristic.value ?? Data()
        guard !data.isEmpty else { return }

        rxBuffer.append(data)
        let frames = BLEConfig.extractFrames(from: &rxBuffer)
        for frame in frames {
            handle(frame: frame)
        }
    }

    private func handle(frame: Data) {
        let bytes = [UInt8](frame)
        guard bytes.count >= 2 else { return }

        switch bytes[1] {
        case BLEConfig.Opcode.statusReport:
            if let parsed = BLEConfig.parseStatus(frame) {
                status = parsed
            } else {
                log("STATUS 帧格式不符：\(hex(frame))")
            }

        case BLEConfig.Opcode.infoReport:
            if let info = BLEConfig.parseInfo(frame) {
                deviceInfo = info
                infoRetryCount = 0
                log("设备识别完成：\(info.summary)  模式表 \(info.modeChannels.map { String(format: "0x%02X", $0) })")
                requestStatus()
            } else {
                log("INFO 帧格式不符：\(hex(frame))")
            }

        case BLEConfig.Opcode.ack:
            if let ack = BLEConfig.parseAck(frame) {
                lastAck = ack
                if !ack.isOK {
                    log("设备拒绝命令 0x\(String(format: "%02X", ack.opcode))：\(ack.reason)")
                }
            }

        default:
            log("← 未知帧 \(hex(frame))")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error { log("写入失败：\(error.localizedDescription)") }
    }

    // MARK: 演示模式

    private func startDemoLoop() {
        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.demoRunning && self.demoRemaining > 0 { self.demoRemaining -= 1 }
            self.publishDemoStatus()
        }
    }

    private func publishDemoStatus() {
        var flags: UInt8 = 0x20                       // powered
        if demoRunning { flags |= 0x01 }
        let frame = BLEConfig.demoStatusFrame(
            mode: demoModeIndex,
            bright: demoBright,
            remainingSeconds: demoRemaining,
            battery: 86,
            flags: flags
        )
        status = BLEConfig.parseStatus(frame)
    }

    private func handleDemoCommand(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 5 else { return }
        // 帧结构 AA OP LEN PAYLOAD SUM 55，负载就是去掉头 3 字节和尾 2 字节
        let payload: [UInt8] = (3..<(b.count - 2)).map { b[$0] }

        switch b[1] {
        case BLEConfig.Opcode.setMode:
            if let first = payload.first, first >= 1, Int(first) <= modeCount {
                demoModeIndex = Int(first)
            }
        case BLEConfig.Opcode.setBright:
            if let first = payload.first, Int(first) < max(1, brightCount) {
                demoBright = Int(first)
            }
        case BLEConfig.Opcode.setTime:
            if let first = payload.first, first >= 1, Int(first) <= durations.count {
                demoRemaining = durations[Int(first) - 1] * 60
            }
        case BLEConfig.Opcode.start:
            if let first = payload.first, first >= 1, Int(first) <= modeCount {
                demoModeIndex = Int(first)
            }
            demoRunning = true
            if demoRemaining == 0, durations.indices.contains(0) {
                demoRemaining = durations[0] * 60
            }
        case BLEConfig.Opcode.stop:
            demoRunning = false
            demoRemaining = 0
        case BLEConfig.Opcode.setAll:
            if payload.count >= 3 {
                if payload[0] >= 1, Int(payload[0]) <= modeCount { demoModeIndex = Int(payload[0]) }
                if Int(payload[1]) < max(1, brightCount) { demoBright = Int(payload[1]) }
                if payload[2] >= 1, Int(payload[2]) <= durations.count {
                    demoRemaining = durations[Int(payload[2]) - 1] * 60
                }
                demoRunning = true
            }
        default:
            break
        }
        publishDemoStatus()
    }

    // MARK: 工具

    func stateText(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "已开启"
        case .poweredOff: return "已关闭"
        case .unauthorized: return "未授权，请到系统设置允许蓝牙"
        case .unsupported: return "设备不支持 BLE"
        case .resetting: return "正在重置"
        case .unknown: return "未知"
        @unknown default: return "未知状态"
        }
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "\(formatter.string(from: Date()))  \(message)"
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.logs.insert(line, at: 0)
            if self.logs.count > 200 { self.logs = Array(self.logs.prefix(200)) }
        }
    }

    func clearLogs() {
        logs.removeAll()
    }
}
