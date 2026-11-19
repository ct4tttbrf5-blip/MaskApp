import SwiftUI

struct ControlView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var session: SessionController

    private var modes: [BLEConfig.TherapyMode] { bluetooth.modes }
    private var isReady: Bool { bluetooth.isDeviceReady }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    connectionBanner

                    if isReady {
                        if let info = bluetooth.deviceInfo {
                            deviceVersionCard(info)
                        }
                        modeSection
                        brightSection
                        durationSection
                        timerCard
                    } else {
                        identifyingCard
                    }

                    if let notice = session.notice {
                        Text(notice)
                            .font(.system(size: 12))
                            .foregroundColor(.maskAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let status = bluetooth.status {
                        deviceStatusRow(status)
                    }
                }
                .padding(16)
            }
            .background(Color.maskBackground.ignoresSafeArea())
            .navigationTitle("护理")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: 连接提示

    private var connectionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: bluetooth.connected == nil ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundColor(bluetooth.connected == nil ? .maskWarning : .maskAccent)
            Text(bluetooth.connected == nil
                 ? "尚未连接设备，请先到「设备」页连接"
                 : "已连接 \(bluetooth.connected?.name ?? "设备")")
                .font(.system(size: 13))
                .foregroundColor(.maskTextSecondary)
            Spacer()
        }
        .maskCard(padding: 12)
    }

    /// 这台机器是 LED 版还是激光版 + 固件版本
    private func deviceVersionCard(_ info: BLEConfig.DeviceInfo) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((info.deviceType == .laser ? Color.maskWarning : Color.maskAccent).opacity(0.16))
                    .frame(width: 46, height: 46)
                Image(systemName: info.deviceType.symbol)
                    .font(.system(size: 20))
                    .foregroundColor(info.deviceType == .laser ? .maskWarning : .maskAccent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(info.deviceType.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.maskText)
                Text("\(info.deviceType.detail) · 固件 \(info.firmwareVersion)")
                    .font(.system(size: 12))
                    .foregroundColor(.maskTextSecondary)
            }
            Spacer()
            Text("\(info.modeChannels.count) 档")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.maskAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.maskAccent.opacity(0.12))
                .clipShape(Capsule())
        }
        .maskCard()
    }

    private var identifyingCard: some View {
        VStack(spacing: 12) {
            Image(systemName: bluetooth.connected == nil ? "wifi.slash" : "arrow.triangle.2.circlepath")
                .font(.system(size: 26))
                .foregroundColor(.maskTextSecondary.opacity(0.7))
            Text(bluetooth.connected == nil
                 ? "先连接面膜才能控制"
                 : "正在识别设备版本，读取可用的护理模式…")
                .font(.system(size: 14))
                .foregroundColor(.maskTextSecondary)
                .multilineTextAlignment(.center)
            if bluetooth.connected != nil {
                Text("若长时间停在这里，请确认固件已烧到 v197 及以上（带 BLE 控制协议）。")
                    .font(.system(size: 11))
                    .foregroundColor(.maskTextSecondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if bluetooth.connected != nil {
                Button("重新读取设备版本") { bluetooth.beginHandshake() }
                    .font(.system(size: 13))
                    .foregroundColor(.maskAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .maskCard()
    }

    // MARK: 模式（LED 版 3 档 / 激光版 2 档，由固件 INFO 决定）

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "护理模式")
                Spacer()
                Text("设备提供 \(modes.count) 档")
                    .font(.system(size: 11))
                    .foregroundColor(.maskTextSecondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(modes) { mode in
                    Button {
                        session.selectedModeIndex = mode.id
                        session.syncSettings()
                    } label: {
                        modeCard(mode)
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isRunning)
                    .opacity(session.isRunning ? 0.6 : 1.0)
                }
            }
        }
    }

    private func modeCard(_ mode: BLEConfig.TherapyMode) -> some View {
        let selected = session.selectedModeIndex == mode.id
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: mode.symbol)
                .font(.system(size: 20))
                .foregroundColor(selected ? .maskAccent : .maskTextSecondary)
            Text(mode.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.maskText)
            Text(mode.subtitle)
                .font(.system(size: 10))
                .foregroundColor(.maskTextSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(selected ? Color.maskAccent.opacity(0.12) : Color.maskCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    selected ? Color.maskAccent : Color.maskBorder.opacity(0.6),
                    lineWidth: selected ? 1.2 : 0.5
                )
        )
    }

    // MARK: 亮度（设备只有 50 / 70 / 90 三档）

    private var brightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "亮度")
                Spacer()
                Text(session.brightText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.maskAccent)
            }
            HStack(spacing: 8) {
                ForEach(Array(0..<max(1, bluetooth.brightCount)), id: \.self) { level in
                    Button {
                        session.setBrightLevel(level)
                    } label: {
                        Text(bleBrightLabel(level))
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(session.brightLevel == level ? Color.maskAccent : Color.maskCardRaised)
                            .foregroundColor(session.brightLevel == level ? .maskBackground : .maskTextSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .maskCard()
            Text(session.isRunning
                 ? "理疗中可直接切换亮度，设备会“嘀”一声并点亮对应档位灯 10 秒。"
                 : "亮度档位由设备硬件决定，App 不做超出范围的设置。")
                .font(.system(size: 11))
                .foregroundColor(.maskTextSecondary.opacity(0.75))
        }
    }

    private func bleBrightLabel(_ level: Int) -> String {
        let percents = BLEConfig.brightPercents
        return percents.indices.contains(level) ? "\(percents[level])%" : "\(level + 1) 档"
    }

    // MARK: 时长（设备只有 5 / 10 / 15 分钟）

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "护理时长")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                ForEach(Array(bluetooth.durations.enumerated()), id: \.offset) { index, minutes in
                    let level = index + 1
                    Button {
                        session.setDurationLevel(level)
                    } label: {
                        Text("\(minutes) 分钟")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(session.durationLevel == level ? Color.maskAccent.opacity(0.16) : Color.maskCardRaised)
                            .foregroundColor(session.durationLevel == level ? .maskAccent : .maskTextSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(session.durationLevel == level ? Color.maskAccent : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .maskCard()
            if session.isRunning {
                Text("理疗中可随时改时长，设备会按新时长重新计时并“嘀”一声。")
                    .font(.system(size: 11))
                    .foregroundColor(.maskTextSecondary.opacity(0.75))
            }
        }
    }

    // MARK: 倒计时与启停

    private var timerCard: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(Color.maskCardRaised, lineWidth: 14)
                    .frame(width: 200, height: 200)
                Circle()
                    .trim(from: 0, to: session.isRunning ? session.progress : 0)
                    .stroke(
                        Color.maskAccent,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.4), value: session.progress)

                VStack(spacing: 6) {
                    Text(session.isRunning ? session.remainingText : String(format: "%02d:00", session.durationMinutes))
                        .font(.system(size: 42, weight: .medium, design: .rounded))
                        .foregroundColor(.maskText)
                        .monospacedDigit()
                    Text(session.isRunning ? "剩余时间" : "准备就绪")
                        .font(.system(size: 12))
                        .foregroundColor(.maskTextSecondary)
                }
            }

            Button {
                if session.isRunning {
                    session.finish(completed: false)
                } else {
                    session.start()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: session.isRunning ? "stop.fill" : "play.fill")
                    Text(session.isRunning ? "结束护理" : "开始护理")
                }
            }
            .buttonStyle(
                PrimaryButtonStyle(
                    tint: session.isRunning ? .maskDanger : .maskAccent,
                    disabled: !isReady
                )
            )
            .disabled(!isReady)
        }
        .frame(maxWidth: .infinity)
        .maskCard(padding: 20)
    }

    // MARK: 设备状态

    private func deviceStatusRow(_ status: BLEConfig.DeviceStatus) -> some View {
        HStack(spacing: 16) {
            Label("\(status.battery)%", systemImage: status.isCharging ? "bolt.fill" : "battery.75")
            Label(status.isRunning ? "运行中" : (status.isPowered ? "待机" : "已关机"),
                  systemImage: "circle.fill")
            Label(bluetooth.modeTitle(status.mode), systemImage: "light.max")
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundColor(.maskTextSecondary)
        .maskCard(padding: 12)
    }
}
