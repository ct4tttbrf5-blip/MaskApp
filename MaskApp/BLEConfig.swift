import Foundation
import CoreBluetooth

// MARK: - 与固件 face_mask_ble.c (协议 v1) 一一对应
//
// 固件侧实现：
//   SDK/apps/soundbox/face_mask/face_mask_ble.c  →  GATT / 帧解析
//   SDK/apps/soundbox/face_mask/face_mask_app.c  →  业务状态机
//
// 服务 0xFFE0
//   0xFFE1  写（APP → 面膜）
//   0xFFE2  通知（面膜 → APP）
//
// 帧格式  AA | OP | LEN | PAYLOAD[LEN] | SUM | 55
//         SUM = (AA + OP + LEN + 所有 PAYLOAD) & 0xFF
//
// 关键设计：APP 不写死"几个模式、多少档、能设多久"，
// 连上后先收一帧 INFO，按设备上报的能力生成界面。
// 于是同一份 App 装上 LED 机就是 3 档、装上激光机就是 2 档，
// 参数上限永远跟着固件走（客户要求：以设备功能为准）。

enum BLEConfig {

    // MARK: 设备发现

    /// 固件广播名（face_mask_config.h 的 FM_BT_NAME）
    static let advertisedNamePrefix = "V3.0-Mask"

    static let serviceUUID = CBUUID(string: "FFE0")
    static let writeUUID = CBUUID(string: "FFE1")
    static let notifyUUID = CBUUID(string: "FFE2")

    /// 扫描时不过滤服务，先看到设备名更利于排错
    static let scanServices: [CBUUID]? = nil

    static let minRSSI = -95

    /// 固件 0xFFE1 同时支持 WRITE 与 WRITE_NO_RSP，用带响应更稳（能看到失败）
    static let writeType: CBCharacteristicWriteType = .withResponse

    /// 单次写入上限，超出会在此处分片（当前所有帧 ≤ 17 字节，实际不会分片）
    static let maxPacketSize = 20

    // MARK: 帧格式

    static let frameHeader: UInt8 = 0xAA
    static let frameFooter: UInt8 = 0x55

    /// 单帧最长（含头尾）。超过说明解析跑飞了，直接丢弃重来。
    static let maxFrameLength = 24

    enum Opcode {
        // 下行
        static let setMode: UInt8 = 0x01
        static let setBright: UInt8 = 0x02
        static let setTime: UInt8 = 0x03
        static let start: UInt8 = 0x04
        static let stop: UInt8 = 0x05
        static let queryStatus: UInt8 = 0x06
        static let queryInfo: UInt8 = 0x07
        static let setAll: UInt8 = 0x08
        // 上行
        static let statusReport: UInt8 = 0x81
        static let infoReport: UInt8 = 0x82
        static let ack: UInt8 = 0x83
    }

    // MARK: 设备版本

    /// 固件用 FM_PRODUCT_VERSION 编译期决定，INFO 帧上报
    enum DeviceType: UInt8 {
        case led = 1
        case laser = 2

        var title: String {
            switch self {
            case .led: return "LED 版"
            case .laser: return "激光版"
            }
        }

        var detail: String {
            switch self {
            case .led: return "460 + 660 + 850nm"
            case .laser: return "460 + 665 + 850 + 1064nm"
            }
        }

        var symbol: String {
            switch self {
            case .led: return "light.max"
            case .laser: return "sparkles"
            }
        }
    }

    // MARK: 光疗通道

    /// 与固件 FM_CH_xxx 一致（bit0 红 / bit1 蓝 / bit2 850 / bit3 1064）
    enum Channel: UInt8 {
        case red = 0x01
        case blue = 0x02
        case ir850 = 0x04
        case laser1064 = 0x08

        var shortName: String {
            switch self {
            case .red: return "红光"
            case .blue: return "蓝光"
            case .ir850: return "850"
            case .laser1064: return "1064"
            }
        }
    }

    static let allChannels: [Channel] = [.red, .blue, .ir850, .laser1064]

    static func channelNames(_ mask: UInt8) -> [String] {
        allChannels.filter { mask & $0.rawValue != 0 }.map(\.shortName)
    }

    // MARK: 一个光疗模式（由设备上报的通道掩码生成）

    struct TherapyMode: Identifiable, Equatable {
        let id: Int          // 1 基，与固件 mode 参数一致
        let channels: UInt8

        var title: String { "模式 \(id)" }

        var subtitle: String {
            let names = BLEConfig.channelNames(channels)
            return names.isEmpty ? "—" : names.joined(separator: " + ")
        }

        /// 含 1064 的模式用激光图标，其余用光疗图标
        var symbol: String {
            channels & Channel.laser1064.rawValue != 0 ? "sparkles" : "light.max"
        }
    }

    // MARK: 设备能力（INFO 帧）

    struct DeviceInfo: Equatable {
        var deviceType: DeviceType
        var modeChannels: [UInt8]
        var brightCount: Int
        var durations: [Int]
        var firmwareVersion: String
        var protocolVersion: Int

        var modes: [TherapyMode] {
            modeChannels.enumerated().map { TherapyMode(id: $0.offset + 1, channels: $0.element) }
        }

        /// 亮度档位名称：固件百分比固定 50 / 70 / 90，档数由设备给
        var brightLabels: [String] {
            let percents = BLEConfig.brightPercents
            return (0..<max(0, brightCount)).map { index in
                index < percents.count ? "\(percents[index])%" : "\(index + 1) 档"
            }
        }

        var summary: String {
            "\(deviceType.title) · \(modeChannels.count) 档模式 · 固件 \(firmwareVersion)"
        }
    }

    /// 固件 FM_BRIGHT_DUTY_50 / 70 / 90（见 face_mask_config.h）
    static let brightPercents = [50, 70, 90]

    // MARK: 设备状态（STATUS 帧）

    struct DeviceStatus: Equatable {
        var mode: Int
        var bright: Int
        var remainingSeconds: Int
        var battery: Int
        var flags: UInt8

        var isRunning: Bool { flags & 0x01 != 0 }
        var isCharging: Bool { flags & 0x02 != 0 }
        var isFull: Bool { flags & 0x04 != 0 }
        var isLowBattery: Bool { flags & 0x08 != 0 }
        var voiceOn: Bool { flags & 0x10 != 0 }
        var isPowered: Bool { flags & 0x20 != 0 }

        /// 亮度百分比文本
        var brightPercentText: String {
            let percents = BLEConfig.brightPercents
            return bright < percents.count ? "\(percents[bright])%" : "\(bright + 1) 档"
        }

        /// 刚连上时设备还没采到电池电压（上报 0），此时显示 -- 而不是 0%
        var batteryText: String { battery > 0 ? "\(battery)%" : "--" }

        // MARK: 电量显示（图标分档 + 低电红）

        /// 低电门限。与固件 face_mask_ble.c 的 FM_BLE_FLAG_LOW_BAT 一致：
        /// 固件是 `battery_pct <= 10` 置位，这里同口径，避免"设备认为低电、
        /// App 认为正常"的两套标准。
        static let lowBatteryThreshold = 10

        /// 电量 0 是"设备还没采到电压"的占位值（开机几秒内会上报 0），
        /// 不能当成"电池耗尽"，否则刚连上就会误报红。
        var hasBatteryReading: Bool { battery > 0 }

        /// 低电：固件标志位与本地百分比任一命中即可，0% 的未知态不算低电
        var isBatteryLow: Bool {
            guard hasBatteryReading else { return false }
            return isLowBattery || battery <= Self.lowBatteryThreshold
        }

        /// 电池图标按电量分档（SF Symbols battery.0/25/50/75/100）。
        /// 充电时用带闪电的满格图标，与数字一起表达"在充"。
        var batterySymbol: String {
            if isCharging { return "battery.100.bolt" }
            guard hasBatteryReading else { return "battery.0" }
            switch battery {
            case 88...: return "battery.100"
            case 63..<88: return "battery.75"
            case 38..<63: return "battery.50"
            case 13..<38: return "battery.25"
            default: return "battery.0"
            }
        }
    }

    // MARK: 指令编码

    static func makeFrame(opcode: UInt8, payload: [UInt8] = []) -> Data {
        var bytes: [UInt8] = [frameHeader, opcode, UInt8(payload.count & 0xFF)]
        bytes.append(contentsOf: payload)
        var sum: UInt8 = 0
        for byte in bytes { sum = sum &+ byte }
        bytes.append(sum)
        bytes.append(frameFooter)
        return Data(bytes)
    }

    /// 切模式：mode 1..modeCount（激光版传 3 会被固件拒，界面上不会出现）
    static func setMode(_ mode: Int) -> Data {
        makeFrame(opcode: Opcode.setMode, payload: [UInt8(clamping: mode)])
    }

    /// 亮度档：0 = 50% / 1 = 70% / 2 = 90%
    static func setBright(_ level: Int) -> Data {
        makeFrame(opcode: Opcode.setBright, payload: [UInt8(clamping: level)])
    }

    /// 定时档：1 = 5min / 2 = 10min / 3 = 15min
    static func setTime(_ level: Int) -> Data {
        makeFrame(opcode: Opcode.setTime, payload: [UInt8(clamping: level)])
    }

    static func start(mode: Int? = nil) -> Data {
        if let mode = mode {
            return makeFrame(opcode: Opcode.start, payload: [UInt8(clamping: mode)])
        }
        return makeFrame(opcode: Opcode.start)
    }

    static func stop() -> Data { makeFrame(opcode: Opcode.stop) }
    static func queryStatus() -> Data { makeFrame(opcode: Opcode.queryStatus) }
    static func queryInfo() -> Data { makeFrame(opcode: Opcode.queryInfo) }

    /// 一次设全并启动，减少往返（固件按 亮度→定时→启动 顺序执行）
    static func setAll(mode: Int, bright: Int, timeLevel: Int) -> Data {
        makeFrame(
            opcode: Opcode.setAll,
            payload: [UInt8(clamping: mode), UInt8(clamping: bright), UInt8(clamping: timeLevel)]
        )
    }

    // MARK: 上行解析

    /// 从接收缓冲里切出完整帧，返回 (帧数组, 剩余字节)
    /// BLE 单次通知一般就是一帧，但 MTU 变大后可能粘包，所以统一走缓冲。
    static func extractFrames(from buffer: inout Data) -> [Data] {
        var frames: [Data] = []

        while buffer.count >= 3 {
            // 对齐帧头
            if buffer[buffer.startIndex] != frameHeader {
                buffer.removeFirst()
                continue
            }
            let length = Int(buffer[buffer.startIndex + 2])
            let total = 3 + length + 2
            guard total <= maxFrameLength else {
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= total else { break }   // 半帧，等下一包

            let start = buffer.startIndex
            let frame = buffer.subdata(in: start..<(start + total))
            guard frame[frame.count - 1] == frameFooter else {
                buffer.removeFirst()                      // 尾字节不对，丢弃重找
                continue
            }
            // 校验和
            var sum: UInt8 = 0
            for index in 0..<(total - 2) { sum = sum &+ frame[index] }
            guard frame[total - 2] == sum else {
                buffer.removeFirst()
                continue
            }

            frames.append(frame)
            buffer.removeFirst(total)
        }
        return frames
    }

    /// STATUS 0x81：mode / bright / 剩余秒(大端) / 电量% / flags
    static func parseStatus(_ data: Data) -> DeviceStatus? {
        let b = [UInt8](data)
        guard b.count == 11, b[0] == frameHeader, b[1] == Opcode.statusReport, b[10] == frameFooter else {
            return nil
        }
        return DeviceStatus(
            mode: Int(b[3]),
            bright: Int(b[4]),
            remainingSeconds: (Int(b[5]) << 8) | Int(b[6]),
            battery: min(100, Int(b[7])),
            flags: b[8]
        )
    }

    /// INFO 0x82：
    /// [dev_type][mode_cnt][bright_cnt][time_cnt][fw_ver][proto_ver]
    /// [mode_ch × mode_cnt][dur_min × time_cnt]
    static func parseInfo(_ data: Data) -> DeviceInfo? {
        let b = [UInt8](data)
        guard b.count >= 11, b[0] == frameHeader, b[1] == Opcode.infoReport, b.last == frameFooter else {
            return nil
        }
        let length = Int(b[2])
        guard b.count == length + 5 else { return nil }

        let payload = Array(b[3..<(3 + length)])
        guard payload.count >= 6 else { return nil }

        let type = DeviceType(rawValue: payload[0]) ?? .led
        let modeCount = Int(payload[1])
        let brightCount = Int(payload[2])
        let timeCount = Int(payload[3])
        let firmware = "v\(payload[4])"
        let protocolVersion = Int(payload[5])

        var cursor = 6
        guard payload.count >= cursor + modeCount + timeCount else { return nil }

        let modeChannels = Array(payload[cursor..<(cursor + modeCount)])
        cursor += modeCount
        let durations = payload[cursor..<(cursor + timeCount)].map { Int($0) }

        return DeviceInfo(
            deviceType: type,
            modeChannels: modeChannels,
            brightCount: brightCount,
            durations: durations,
            firmwareVersion: firmware,
            protocolVersion: protocolVersion
        )
    }

    /// ACK 0x83：[op][code]  code 0=OK 1=参数超范围 2=状态不允许 3=未知命令
    struct Ack: Equatable {
        var opcode: UInt8
        var code: UInt8
        var isOK: Bool { code == 0 }

        var reason: String {
            switch code {
            case 0: return "成功"
            case 1: return "参数超出设备范围"
            case 2: return "设备当前状态不允许（充电中或已关机）"
            default: return "设备不认识这条命令"
            }
        }
    }

    static func parseAck(_ data: Data) -> Ack? {
        let b = [UInt8](data)
        guard b.count == 7, b[0] == frameHeader, b[1] == Opcode.ack, b[6] == frameFooter else {
            return nil
        }
        return Ack(opcode: b[3], code: b[4])
    }

    // MARK: 演示模式

    /// 没有硬件时用这份数据预览界面；demonType 可在「设置」里切换
    static func demoInfo(type: DeviceType) -> DeviceInfo {
        switch type {
        case .led:
            // 与固件 LED 版一致：1=红+850+Q5  2=蓝+Q5  3=全开
            return DeviceInfo(
                deviceType: .led,
                modeChannels: [0x07, 0x0A, 0x0F],
                brightCount: 3,
                durations: [5, 10, 15],
                firmwareVersion: "v197(演示)",
                protocolVersion: 1
            )
        case .laser:
            // 与固件激光版一致：1=红+850+1064  2=蓝+1064
            return DeviceInfo(
                deviceType: .laser,
                modeChannels: [0x0D, 0x0A],
                brightCount: 3,
                durations: [5, 10, 15],
                firmwareVersion: "v197(演示)",
                protocolVersion: 1
            )
        }
    }

    static func demoStatusFrame(mode: Int, bright: Int, remainingSeconds: Int, battery: Int, flags: UInt8) -> Data {
        let seconds = UInt16(max(0, min(65535, remainingSeconds)))
        return makeFrame(
            opcode: Opcode.statusReport,
            payload: [
                UInt8(clamping: mode),
                UInt8(clamping: bright),
                UInt8(seconds >> 8),
                UInt8(seconds & 0xFF),
                UInt8(clamping: battery),
                flags
            ]
        )
    }
}
