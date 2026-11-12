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

final class BluetoothManager: NSObject, ObservableObject {

    // MARK: 界面状态

    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var connected: DiscoveredDevice?
    @Published private(set) var status: BLEConfig.DeviceStatus?
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

    /// 协议未确定时默认显示周边全部 BLE 设备，方便先找到设备名和 UUID。
    /// 确认后可关掉，仅显示 BLEConfig.advertisedNamePrefix 开头的设备。
    @Published var showAllDevices: Bool = true

    private static let demoKey = "maskapp.demoMode"

    // MARK: 私有状态

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var reconnectID: UUID?

    private var demoTimer: Timer?
    private var demoRemaining = 0
    private var demoRunning = false
    private var demoModeValue: BLEConfig.Mode = .led
    private var demoIntensity = 3

    override init() {
        demoMode = UserDefaults.standard.bool(forKey: Self.demoKey)
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: 扫描

    func startScan() {
        guard !isScanning else { return }
        if demoMode {
            startDemoScan()
            return
        }
        guard central.state == .poweredOn else {
            log("蓝牙未就绪，无法扫描：\(stateText(central.state))")
            return
        }
        devices.removeAll()
        isScanning = true
        central.scanForPeripherals(
            withServices: BLEConfig.scanServices,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        log("开始扫描周边 BLE 设备")
    }

    func stopScan() {
        if !demoMode, central.state == .poweredOn { central.stopScan() }
        isScanning = false
    }

    private func startDemoScan() {
        devices = [
            DiscoveredDevice(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "DN-MASK-3.0（演示）",
                rssi: -52,
                isDemo: true
            ),
            DiscoveredDevice(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                name: "DN-MASK-3.0-2（演示）",
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
            demoRemaining = 0
            demoRunning = false
            log("已连接 \(device.name)")
            startDemoLoop()
            publishDemoStatus()
            return
        }
        guard let target = peripherals[device.id], central.state == .poweredOn else {
            log("连接失败：找不到设备或蓝牙未就绪")
            return
        }
        reconnectID = device.id
        target.delegate = self
        log("正在连接 \(device.name)…")
        central.connect(target, options: nil)
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
        devices.removeAll()
    }

    // MARK: 指令下发

    func applyMode(_ mode: BLEConfig.Mode) {
        send(BLEConfig.setMode(mode), label: "设置模式 \(mode.title)")
    }

    func applyIntensity(_ level: Int) {
        send(BLEConfig.setIntensity(level), label: "设置档位 \(level)")
    }

    func applyDuration(_ minutes: Int) {
        send(BLEConfig.setDuration(minutes), label: "设置时长 \(minutes) 分钟")
    }

    func startTreatment() {
        send(BLEConfig.start(), label: "开始护理")
    }

    func stopTreatment() {
        send(BLEConfig.stop(), label: "停止护理")
    }

    func requestStatus() {
        send(BLEConfig.queryStatus(), label: "查询状态")
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
        connected = devices.first(where: { $0.id == peripheral.identifier })
            ?? DiscoveredDevice(
                id: peripheral.identifier,
                name: peripheral.name ?? "电子面膜",
                rssi: 0,
                isDemo: false
            )
        log("已连接 \(connected?.name ?? "设备")")
        // 发现全部服务并打印 UUID，方便按真实协议填写 BLEConfig.swift
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        log("连接失败：\(error?.localizedDescription ?? "未知原因")")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        log("连接断开：\(error?.localizedDescription ?? "主动断开")")
        connected = nil
        status = nil
        if let id = reconnectID, let target = peripherals[id], central.state == .poweredOn {
            log("尝试自动重连…")
            central.connect(target, options: nil)
        }
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error { log("服务发现失败：\(error.localizedDescription)") }
        let services = peripheral.services ?? []
        if services.isEmpty { log("未发现任何服务，请确认设备是否支持 BLE") }
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
                log("  → 已匹配写特征")
            }
            if characteristic.uuid == BLEConfig.notifyUUID {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                log("  → 已匹配通知特征")
            }
        }

        // 占位 UUID 尚未按真实固件修改时，自动挑一个可用的特征，
        // 让首次调试也能连通。确认协议后把 UUID 填进 BLEConfig 即可。
        let all = (peripheral.services ?? []).flatMap { $0.characteristics ?? [] }
        if writeCharacteristic == nil,
           let fallback = all.first(where: { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }) {
            writeCharacteristic = fallback
            log("  → 未匹配写特征，临时自动选用 \(fallback.uuid.uuidString)")
        }
        if notifyCharacteristic == nil,
           let fallback = all.first(where: { $0.properties.contains(.notify) }) {
            notifyCharacteristic = fallback
            peripheral.setNotifyValue(true, for: fallback)
            log("  → 未匹配通知特征，临时自动选用 \(fallback.uuid.uuidString)")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error { log("订阅通知失败：\(error.localizedDescription)") }
        else { log("已订阅 \(characteristic.uuid.uuidString) 通知") }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error { log("读取失败：\(error.localizedDescription)") }
        let data = characteristic.value ?? Data()
        log("← 状态数据 \(hex(data))")
        if let parsed = BLEConfig.parseStatus(data) {
            status = parsed
        } else {
            log("状态格式不匹配，请按固件协议调整 BLEConfig.parseStatus")
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
        let frame = BLEConfig.demoStatusFrame(
            mode: demoModeValue,
            intensity: demoIntensity,
            remainingSeconds: demoRemaining,
            battery: 86,
            isRunning: demoRunning
        )
        status = BLEConfig.parseStatus(frame)
    }

    private func handleDemoCommand(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 2 else { return }
        switch b[1] {
        case BLEConfig.Opcode.setMode:
            if b.count > 3, let m = BLEConfig.Mode(rawValue: b[3]) { demoModeValue = m }
        case BLEConfig.Opcode.setIntensity:
            if b.count > 3 { demoIntensity = Int(b[3]) }
        case BLEConfig.Opcode.setDuration:
            if b.count > 4 { demoRemaining = (Int(b[3]) << 8) | Int(b[4]) }
        case BLEConfig.Opcode.start:
            demoRunning = true
        case BLEConfig.Opcode.stop:
            demoRunning = false
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
