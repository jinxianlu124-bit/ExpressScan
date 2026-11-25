import SwiftUI
import SwiftData

@main
struct ExpressScanApp: App {
    init() {
        // 冷启动（进程新起）结束上一次扫码会话：记录页不再显示之前的记录。
        ScanSession.resetOnAppStart()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: ScanRecord.self)
        }
    }
}
