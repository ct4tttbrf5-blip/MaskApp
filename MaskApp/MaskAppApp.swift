import SwiftUI

@main
struct MaskAppApp: App {
    @StateObject private var bluetooth: BluetoothManager
    @StateObject private var session: SessionController

    init() {
        let manager = BluetoothManager()
        _bluetooth = StateObject(wrappedValue: manager)
        _session = StateObject(wrappedValue: SessionController(bluetooth: manager))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(bluetooth)
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}
