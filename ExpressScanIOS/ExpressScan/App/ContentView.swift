import SwiftData
import SwiftUI
import UIKit

/// 根视图：扫码 / 记录 / 生成 三个标签页 + 启动时的版本检查。
struct ContentView: View {
    enum Tab: Hashable { case scan, records, generate }

    @State private var tab: Tab = .scan
    @State private var recordsShowHistory = false
    @State private var update: UpdateInfo?

    var body: some View {
        TabView(selection: $tab) {
            ScanView {
                recordsShowHistory = true
                tab = .records
            }
            .tabItem { Label("扫码", systemImage: "qrcode.viewfinder") }
            .tag(Tab.scan)

            NavigationStack {
                RecordsView(showHistory: $recordsShowHistory)
            }
            .tabItem { Label("记录", systemImage: "list.bullet") }
            .tag(Tab.records)

            NavigationStack {
                GenerateView()
            }
            .tabItem { Label("生成", systemImage: "barcode") }
            .tag(Tab.generate)
        }
        .task { update = await UpdateChecker.check() }
        .alert("发现新版本", isPresented: Binding(get: { update != nil }, set: { if !$0 { update = nil } })) {
            Button("前往更新") {
                if let url = URL(string: UpdateChecker.downloadPage) {
                    UIApplication.shared.open(url)
                }
                update = nil
            }
            Button("下次再说", role: .cancel) { update = nil }
        } message: {
            Text(update?.notes ?? "有可用的新版本。")
        }
    }
}
