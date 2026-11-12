import SwiftUI

struct ControlView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var session: SessionController

    private var availableModes: [BLEConfig.Mode] {
        BLEConfig.showLaserMode ? Array(BLEConfig.Mode.allCases) : [.led]
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    connectionBanner
                    modeSection
                    intensitySection
                    durationSection
                    timerCard
                    if let notice = session.notice {
                        Text(notice)
                            .font(.system(size: 12))
                            .foregroundColor(.maskAccent)
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

    // MARK: 模式

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "护理模式")
            HStack(spacing: 12) {
                ForEach(availableModes) { mode in
                    Button {
                        session.selectedMode = mode
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

    private func modeCard(_ mode: BLEConfig.Mode) -> some View {
        let selected = session.selectedMode == mode
        return VStack(alignment: .leading, spacing: 10) {
            Image(systemName: mode.symbol)
                .font(.system(size: 22))
                .foregroundColor(selected ? .maskAccent : .maskTextSecondary)
            Text(mode.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.maskText)
            Text(mode.subtitle)
                .font(.system(size: 11))
                .foregroundColor(.maskTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
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

    // MARK: 档位

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "强度档位")
                Spacer()
                Text("\(session.intensity) 档")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.maskAccent)
            }
            HStack(spacing: 8) {
                ForEach(Array(BLEConfig.intensityRange), id: \.self) { level in
                    Button {
                        session.intensity = level
                        session.syncSettings()
                    } label: {
                        Text("\(level)")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(session.intensity == level ? Color.maskAccent : Color.maskCardRaised)
                            .foregroundColor(session.intensity == level ? .maskBackground : .maskTextSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isRunning)
                }
            }
            .maskCard()
        }
    }

    // MARK: 时长

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "护理时长")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                ForEach(BLEConfig.durationOptions, id: \.self) { minutes in
                    Button {
                        session.durationMinutes = minutes
                        session.syncSettings()
                    } label: {
                        Text("\(minutes) 分钟")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(session.durationMinutes == minutes ? Color.maskAccent.opacity(0.16) : Color.maskCardRaised)
                            .foregroundColor(session.durationMinutes == minutes ? .maskAccent : .maskTextSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(session.durationMinutes == minutes ? Color.maskAccent : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isRunning)
                }
            }
            .maskCard()
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
                    disabled: bluetooth.connected == nil
                )
            )
            .disabled(bluetooth.connected == nil)
        }
        .frame(maxWidth: .infinity)
        .maskCard(padding: 20)
    }

    // MARK: 设备状态

    private func deviceStatusRow(_ status: BLEConfig.DeviceStatus) -> some View {
        HStack(spacing: 18) {
            Label("\(status.battery)%", systemImage: "battery.75")
            Label(status.isRunning ? "运行中" : "待机", systemImage: "circle.fill")
            Label("\(status.intensity) 档", systemImage: "dial.min")
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundColor(.maskTextSecondary)
        .maskCard(padding: 12)
    }
}
