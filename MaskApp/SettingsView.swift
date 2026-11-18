import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var showAllLogs = false

    private var visibleLogs: [String] {
        Array(bluetooth.logs.prefix(showAllLogs ? 200 : 6))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    togglesCard
                    protocolCard
                    logsCard
                    aboutCard
                }
                .padding(16)
            }
            .background(Color.maskBackground.ignoresSafeArea())
            .navigationTitle("设置")
        }
        .navigationViewStyle(.stack)
    }

    private var togglesCard: some View {
        VStack(spacing: 14) {
            Toggle(isOn: $bluetooth.demoMode) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("演示模式")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.maskText)
                    Text("不调用真实蓝牙，用模拟设备预览全部功能")
                        .font(.system(size: 11))
                        .foregroundColor(.maskTextSecondary)
                }
            }
            .tint(.maskAccent)

            if bluetooth.demoMode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("演示设备版本")
                        .font(.system(size: 12))
                        .foregroundColor(.maskTextSecondary)
                    Picker("演示设备版本", selection: $bluetooth.demoDeviceType) {
                        Text("LED 版（3 档）").tag(BLEConfig.DeviceType.led)
                        Text("激光版（2 档）").tag(BLEConfig.DeviceType.laser)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Divider().background(Color.maskBorder)

            Toggle(isOn: $bluetooth.showAllDevices) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("显示周边全部 BLE 设备")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.maskText)
                    Text("首次找设备时开启，确认名称后可关闭以便过滤")
                        .font(.system(size: 11))
                        .foregroundColor(.maskTextSecondary)
                }
            }
            .tint(.maskAccent)
        }
        .maskCard()
    }

    private var protocolCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "设备协议")
            Text("服务 0xFFE0 · 写 0xFFE1 · 通知 0xFFE2，帧格式 AA/OP/LEN/PAYLOAD/SUM/55。连上后先收 INFO 帧，按设备上报的模式数量、亮度档数、时长表生成界面。")
                .font(.system(size: 12))
                .foregroundColor(.maskTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("所以同一份 App：接 LED 机显示 3 档模式，接激光机显示 2 档模式；参数上限一律以设备为准，App 不会下发超范围的值。")
                .font(.system(size: 12))
                .foregroundColor(.maskAccent)
                .fixedSize(horizontal: false, vertical: true)
            Text("固件需 v197 及以上（face_mask_ble.c 协议 v1）。面膜关机状态下不广播，扫描前请长按电源键 2 秒开机。")
                .font(.system(size: 11))
                .foregroundColor(.maskTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .maskCard()
    }

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "蓝牙调试日志  \(bluetooth.logs.count)")
                Spacer()
                if !bluetooth.logs.isEmpty {
                    Button("清空") { bluetooth.clearLogs() }
                        .font(.system(size: 12))
                        .foregroundColor(.maskDanger)
                }
            }

            if bluetooth.logs.isEmpty {
                Text("暂无日志。连接设备或下发指令后，这里会显示原始十六进制数据。")
                    .font(.system(size: 12))
                    .foregroundColor(.maskTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(visibleLogs.indices, id: \.self) { index in
                        Text(visibleLogs[index])
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.maskTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if bluetooth.logs.count > 6 {
                    Button(showAllLogs ? "收起" : "展开全部") {
                        withAnimation { showAllLogs.toggle() }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.maskAccent)
                }
            }
        }
        .maskCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "关于")
            Text("电子面膜 3.0 控制端 · v1.1.1")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.maskText)
            if let info = bluetooth.deviceInfo {
                Text("当前设备：\(info.deviceType.title) · \(info.modeChannels.count) 档模式 · 固件 \(info.firmwareVersion)")
                    .font(.system(size: 12))
                    .foregroundColor(.maskTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("本机通过 AltStore 侧载安装：免费 Apple ID 签名有效期 7 天，到期前需连电脑续签一次。若后续改用开发者账号 TestFlight 分发，则无此限制。")
                .font(.system(size: 12))
                .foregroundColor(.maskTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .maskCard()
    }
}
