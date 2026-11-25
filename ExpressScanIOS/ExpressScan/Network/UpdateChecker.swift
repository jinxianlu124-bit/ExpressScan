import Foundation

struct UpdateInfo: Decodable {
    let versionCode: Int
    let versionName: String
    let apkUrl: String
    let notes: String?
    /// iOS 独立版本号：iOS 不能装 APK，必须单独比对，否则会被安卓的版本号一直提示
    let iosVersionCode: Int?
    let iosVersionName: String?
}

/// 版本检查（iOS 不能像 Android 那样下载安装包静默安装，
/// 因此这里只负责提示：引导去下载页 / TestFlight 更新）。
enum UpdateChecker {
    /// 版本清单地址（与 Android 共用同一份云端清单）。
    static let updateURL = "https://expressscan-update.app.workbuddy.host/update.json?sharecode=J3J4HTJXIT"
    /// 下载/更新引导页；换成 TestFlight 链接即可引导 TestFlight 更新。
    static let downloadPage = "https://expressscan-update.app.workbuddy.host/?sharecode=J3J4HTJXIT"

    /// iOS 版自身版本号（对应清单里的 iosVersionCode，2.0 起支持蓝牙打印）。
    static let localVersionCode = 2

    static func check() async -> UpdateInfo? {
        guard let url = URL(string: updateURL) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
            // 清单里没有 iOS 版本号时不做提示：iOS 只能源码重装，提示也没法一键升级
            guard let iosCode = info.iosVersionCode else { return nil }
            return iosCode > localVersionCode ? info : nil
        } catch {
            return nil
        }
    }
}
