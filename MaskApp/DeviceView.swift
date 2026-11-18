import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    scanButton
                    if let device = bluetooth.connected {
                        connectedCard(device)
                    }
                    deviceList
                    if bluetooth.demoMode {
                        hintCard
                    }
                }
                .padding(16)
            }
            .background(Color.maskBackground.ignoresSafeArea())
            .navigationTitle("设备")
            .onAppear {
                // 进页面就自动扫一次：以前要手动点，且蓝牙刚上电时点了没反应
                if !bluetooth.demoMode, bluetooth.connected == nil, !bluetooth.isScanning {
                    bluetooth.startScan()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.maskAccent.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: bluetooth.demoMode ? "wand.and.stars" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 19))
                    .foregroundColor(.maskAccent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(bluetooth.demoMode ? "演示模式" : "蓝牙 \(bluetooth.stateText(bluetooth.bluetoothState))")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.maskText)
                Text(bluetooth.demoMode ? "无需硬件，用模拟设备预览全部功能" : "请确保面膜已开机并靠近手机")
                    .font(.system(size: 12))
                    .foregroundColor(.maskTextSecondary)
            }
            Spacer()
        }
        .maskCard()
    }

    private var scanButton: some View {
        Button {
            if bluetooth.isScanning { bluetooth.stopScan() }
            else { bluetooth.startScan() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: bluetooth.isScanning ? "stop.circle" : "magnifyingglass")
                Text(bluetooth.isScanning ? "停止扫描" : "扫描附近设备")
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.maskBackground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(bluetooth.isScanning ? Color.maskWarning : Color.maskAccent)
            )
        }
        .buttonStyle(.plain)
    }

    private func connectedCard(_ device: DiscoveredDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.maskAccent)
                Text("已连接")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.maskAccent)
                Spacer()
                Button("断开") { bluetooth.disconnect() }
                    .font(.system(size: 14))
                    .foregroundColor(.maskDanger)
            }
            Text(device.name)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.maskText)
            if let info = bluetooth.deviceInfo {
                HStack(spacing: 6) {
                    Image(systemName: info.deviceType.symbol)
                        .font(.system(size: 11))
                    Text("\(info.deviceType.title) · \(info.modeChannels.count) 档模式 · 固件 \(info.firmwareVersion)")
                        .font(.system(size: 12))
                }
                .foregroundColor(info.deviceType == .laser ? .maskWarning : .maskAccent)
            }
            HStack(spacing: 18) {
                if let status = bluetooth.status {
                    Label("电量 \(status.battery)%", systemImage: "battery.75")
                    Label(status.isRunning ? bluetooth.modeTitle(status.mode) : "待机", systemImage: "light.max")
                } else {
                    Label("等待设备状态上报", systemImage: "ellipsis")
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.maskTextSecondary)
        }
        .maskCard()
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "附近设备  \(bluetooth.devices.count)")

            if bluetooth.devices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 28))
                        .foregroundColor(.maskTextSecondary.opacity(0.55))
                    Text(bluetooth.isScanning
                         ? "正在搜索…（面膜关机时不广播，请先长按电源键 2 秒开机）"
                         : "还没有发现设备。检查：①面膜已长按开机 ②手机「设置→隐私与安全性→蓝牙」允许本 App ③面膜离手机 1 米内")
                        .font(.system(size: 13))
                        .foregroundColor(.maskTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .maskCard()
            } else {
                ForEach(sortedDevices) { device in
                    Button {
                        bluetooth.connect(device)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill((isMask(device) ? Color.maskAccent : Color.maskAccentBlue).opacity(0.14))
                                    .frame(width: 38, height: 38)
                                Image(systemName: isMask(device) ? "face.smiling" : "sparkles")
                                    .foregroundColor(isMask(device) ? .maskAccent : .maskAccentBlue)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(device.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.maskText)
                                    if isMask(device), !device.isDemo {
                                        Text("面膜")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.maskAccent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.maskAccent.opacity(0.14))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(device.isDemo ? "模拟设备 · 点击连接" : "\(device.rssi) dBm · 点击连接")
                                    .font(.system(size: 12))
                                    .foregroundColor(.maskTextSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13))
                                .foregroundColor(.maskTextSecondary)
                        }
                        .maskCard(padding: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 名字匹配面膜广播名的排在最前，其余按信号排序，避免在几十个设备里找
    private var sortedDevices: [DiscoveredDevice] {
        bluetooth.devices.sorted { a, b in
            let am = isMask(a), bm = isMask(b)
            if am != bm { return am }
            return a.rssi > b.rssi
        }
    }

    private func isMask(_ device: DiscoveredDevice) -> Bool {
        device.name.hasPrefix(BLEConfig.advertisedNamePrefix)
    }

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "关于演示模式")
            Text("当前不会调用真实蓝牙。可在「设置」里切换演示的是 LED 版还是激光版，用来预览两种机型各自的控制界面。")
                .font(.system(size: 12))
                .foregroundColor(.maskTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .maskCard()
    }
}
