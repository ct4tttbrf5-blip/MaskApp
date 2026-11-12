import Foundation
import CoreBluetooth

// MARK: - 唯一需要按真实固件协议修改的文件
//
// 拿到电子面膜 3.0 的 BLE 通信协议后，只改本文件即可，其余代码不用动。
// 每一项都标了「占位」，请按固件实际值替换。
//
// 约定：帧格式 = [头][操作码][长度][数据...][校验(可选)][尾]
//       状态上报 = [头][0x81][长度][模式][档位][剩余秒高][剩余秒低][电量][运行][校验][尾]
// 若固件用的是完全不同的协议（自定义服务、无帧头、JSON over BLE 等），
// 只需重写下面的 makeFrame / 各个指令函数 / parseStatus 三个入口。

enum BLEConfig {

    // MARK: 设备发现

    /// 占位：设备广播名前缀，用于过滤扫描结果。留空则不过滤。
    static let advertisedNamePrefix = "DN-MASK"

    /// 占位：主服务 UUID
    static let serviceUUID = CBUUID(string: "FFF0")

    /// 占位：写特征 UUID（App → 设备）
    static let writeUUID = CBUUID(string: "FFF1")

    /// 占位：通知特征 UUID（设备 → App）
    static let notifyUUID = CBUUID(string: "FFF2")

    /// nil 表示扫描周边全部 BLE 设备，首次找设备时更方便。
    /// 确认 UUID 后可改成 [serviceUUID] 以缩小范围、降低耗电。
    static let scanServices: [CBUUID]? = nil

    /// 信号弱于该值的设备不显示
    static let minRSSI = -90

    /// 写入方式：.withResponse 更可靠，.withoutResponse 更快
    static let writeType: CBCharacteristicWriteType = .withResponse

    /// 单次写入最大字节数，超出会在此处分片
    static let maxPacketSize = 20

    // MARK: 界面可选功能

    /// 固件按项目约定统一以 LED 模式编译一遍。
    /// 若首版不需要激光入口，改成 false 即可隐藏，不需要动界面代码。
    static let showLaserMode = true

    /// 档位范围
    static let intensityRange = 1...5

    /// 可选护理时长（分钟）
    static let durationOptions = [5, 10, 15, 20, 30]

    // MARK: 帧格式

    static let frameHeader: UInt8 = 0xAA
    static let frameFooter: UInt8 = 0x55
    static let useChecksum = true

    enum Opcode {
        static let setMode: UInt8 = 0x01
        static let setIntensity: UInt8 = 0x02
        static let setDuration: UInt8 = 0x03
        static let start: UInt8 = 0x04
        static let stop: UInt8 = 0x05
        static let queryStatus: UInt8 = 0x06
        static let statusReport: UInt8 = 0x81
    }

    enum Mode: UInt8, CaseIterable, Identifiable {
        case led = 0x01
        case laser = 0x02

        var id: UInt8 { rawValue }

        var title: String {
            switch self {
            case .led: return "LED 模式"
            case .laser: return "激光模式"
            }
        }

        var subtitle: String {
            switch self {
            case .led: return "红光 / 近红外护理"
            case .laser: return "低能量激光护理"
            }
        }

        var symbol: String {
            switch self {
            case .led: return "light.max"
            case .laser: return "sparkles"
            }
        }
    }

    // MARK: 指令编码

    static func makeFrame(opcode: UInt8, payload: [UInt8] = []) -> Data {
        var bytes: [UInt8] = [frameHeader, opcode, UInt8(payload.count)]
        bytes.append(contentsOf: payload)
        if useChecksum {
            var sum: UInt8 = 0
            for byte in bytes { sum = sum &+ byte }
            bytes.append(sum)
        }
        bytes.append(frameFooter)
        return Data(bytes)
    }

    static func setMode(_ mode: Mode) -> Data {
        makeFrame(opcode: Opcode.setMode, payload: [mode.rawValue])
    }

    static func setIntensity(_ level: Int) -> Data {
        let clamped = min(intensityRange.upperBound, max(intensityRange.lowerBound, level))
        return makeFrame(opcode: Opcode.setIntensity, payload: [UInt8(clamped)])
    }

    /// 时长以秒为单位，大端 UInt16 下发
    static func setDuration(_ minutes: Int) -> Data {
        let seconds = UInt16(min(60, max(1, minutes)) * 60)
        return makeFrame(
            opcode: Opcode.setDuration,
            payload: [UInt8(seconds >> 8), UInt8(seconds & 0xFF)]
        )
    }

    static func start() -> Data { makeFrame(opcode: Opcode.start) }
    static func stop() -> Data { makeFrame(opcode: Opcode.stop) }
    static func queryStatus() -> Data { makeFrame(opcode: Opcode.queryStatus) }

    // MARK: 状态解析

    struct DeviceStatus: Equatable {
        var mode: Mode
        var intensity: Int
        var remainingSeconds: Int
        var battery: Int
        var isRunning: Bool
    }

    /// 把设备上报的原始数据解析成界面可用的状态。
    /// 解析不了时返回 nil，界面会显示「未收到状态上报」，不会崩溃。
    static func parseStatus(_ data: Data) -> DeviceStatus? {
        let b = [UInt8](data)
        guard b.count >= 10,
              b[0] == frameHeader,
              b[1] == Opcode.statusReport,
              b.last == frameFooter else { return nil }

        let mode = Mode(rawValue: b[3]) ?? .led
        let intensity = Int(b[4])
        let remaining = (Int(b[5]) << 8) | Int(b[6])
        let battery = min(100, Int(b[7]))
        let running = b[8] == 0x01

        return DeviceStatus(
            mode: mode,
            intensity: intensity,
            remainingSeconds: remaining,
            battery: battery,
            isRunning: running
        )
    }

    /// 仅供演示模式使用：造一帧和真实设备格式一致的状态数据，
    /// 这样演示与真机走的是同一套解析逻辑，方便提前验证协议代码。
    static func demoStatusFrame(
        mode: Mode,
        intensity: Int,
        remainingSeconds: Int,
        battery: Int,
        isRunning: Bool
    ) -> Data {
        let seconds = UInt16(max(0, remainingSeconds))
        return makeFrame(
            opcode: Opcode.statusReport,
            payload: [
                mode.rawValue,
                UInt8(intensity),
                UInt8(seconds >> 8),
                UInt8(seconds & 0xFF),
                UInt8(battery),
                isRunning ? 0x01 : 0x00
            ]
        )
    }
}
