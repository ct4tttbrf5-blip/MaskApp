import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var selection = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.maskCard)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selection) {
            DeviceView()
                .tabItem { Label("设备", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(0)

            ControlView()
                .tabItem { Label("护理", systemImage: "light.max") }
                .tag(1)

            HistoryView()
                .tabItem { Label("记录", systemImage: "clock") }
                .tag(2)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(.maskAccent)
        .background(Color.maskBackground.ignoresSafeArea())
        .onAppear {
            if bluetooth.demoMode { bluetooth.startScan() }
        }
    }
}
