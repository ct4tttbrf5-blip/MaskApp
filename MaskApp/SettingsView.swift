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
            SectionTitle(text: "接入真实设备前")
            Text("打开工程里的 BLEConfig.swift，把固件实际的服务 UUID、写特征 / 通知特征 UUID 和指令字节填进去，其余代码无需改动。")
                .font(.system(size: 12))
                .foregroundColor(.maskTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("提示：关闭演示模式后扫描真机，下方调试日志会列出设备全部服务与特征 UUID，照抄到配置文件即可。")
                .font(.system(size: 12))
                .foregroundColor(.maskAccent)
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
            Text("电子面膜 3.0 控制端 · v1.0.0")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.maskText)
            Text("本机通过 AltStore 侧载安装：免费 Apple ID 签名有效期 7 天，到期前需连电脑续签一次。若后续改用开发者账号 TestFlight 分发，则无此限制。")
                .font(.system(size: 12))
                .foregroundColor(.maskTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .maskCard()
    }
}
