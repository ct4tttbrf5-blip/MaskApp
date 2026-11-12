import SwiftUI

private extension SessionRecord {
    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    var durationText: String {
        String(format: "%d:%02d", actualSeconds / 60, actualSeconds % 60)
    }
}

struct HistoryView: View {
    @EnvironmentObject private var session: SessionController
    @State private var showClearConfirm = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    statsCard

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionTitle(text: "护理记录  \(session.records.count)")
                            Spacer()
                            if !session.records.isEmpty {
                                Button("清空") { showClearConfirm = true }
                                    .font(.system(size: 13))
                                    .foregroundColor(.maskDanger)
                            }
                        }

                        if session.records.isEmpty {
                            emptyCard
                        } else {
                            ForEach(session.records) { record in
                                recordRow(record)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.maskBackground.ignoresSafeArea())
            .navigationTitle("记录")
            .alert("清空全部记录？", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) { }
                Button("清空", role: .destructive) { session.clearRecords() }
            } message: {
                Text("此操作不可撤销。")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var statsCard: some View {
        HStack(spacing: 8) {
            statItem(value: "\(session.totalSessions)", label: "累计次数")
            Divider().background(Color.maskBorder)
            statItem(value: "\(session.totalMinutes)", label: "累计分钟")
            Divider().background(Color.maskBorder)
            statItem(value: "\(session.records.filter(\.completed).count)", label: "完成次数")
        }
        .maskCard(padding: 16)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(.maskAccent)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.maskTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 28))
                .foregroundColor(.maskTextSecondary.opacity(0.55))
            Text("还没有护理记录")
                .font(.system(size: 13))
                .foregroundColor(.maskTextSecondary)
            Text("完成一次护理后，这里会自动记录模式、档位和时长")
                .font(.system(size: 11))
                .foregroundColor(.maskTextSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .maskCard()
    }

    private func recordRow(_ record: SessionRecord) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(record.completed ? Color.maskAccent.opacity(0.14) : Color.maskWarning.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: record.completed ? "checkmark" : "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(record.completed ? .maskAccent : .maskWarning)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(record.modeTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.maskText)
                Text("\(record.dateText) · \(record.intensity) 档 · 计划 \(record.plannedMinutes) 分钟")
                    .font(.system(size: 11))
                    .foregroundColor(.maskTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(record.durationText)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.maskText)
                Text(record.completed ? "已完成" : "提前结束")
                    .font(.system(size: 11))
                    .foregroundColor(record.completed ? .maskAccent : .maskWarning)
            }
        }
        .maskCard(padding: 12)
    }
}
