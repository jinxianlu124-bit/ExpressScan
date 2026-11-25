import Foundation

/// 扫码会话：定义「一次记录」的边界（与 Android 版规则一致）。
///
/// - 连续两次扫码间隔不超过 5 分钟 → 属于同一次记录；
/// - 超过 5 分钟没扫码、或 App 进程被关闭后重新打开 → 上一次记录结束；
/// - 「记录」页只显示当前会话内的扫码，完整数据永久保留在「全部历史」中。
enum ScanSession {
    private static let startKey = "scan_session.start"
    private static let lastKey = "scan_session.last"
    private static let gap: TimeInterval = 5 * 60

    /// App 冷启动时调用：结束上一次会话。
    static func resetOnAppStart() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: startKey)
        defaults.removeObject(forKey: lastKey)
    }

    /// 每次扫码入库前调用：必要时开启新会话，返回当前会话开始时间。
    @discardableResult
    static func onScan(now: Date = .now) -> Date {
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: lastKey) as? TimeInterval ?? 0
        let start: Date
        if last > 0 && now.timeIntervalSince1970 - last <= gap {
            start = Date(
                timeIntervalSince1970: defaults.object(forKey: startKey) as? TimeInterval
                    ?? now.timeIntervalSince1970
            )
        } else {
            start = now
        }
        defaults.set(start.timeIntervalSince1970, forKey: startKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastKey)
        return start
    }

    /// 当前活动会话的开始时间；nil 表示当前没有进行中的记录。
    static func currentSessionStart() -> Date? {
        let defaults = UserDefaults.standard
        guard let start = defaults.object(forKey: startKey) as? TimeInterval else { return nil }
        let last = defaults.object(forKey: lastKey) as? TimeInterval ?? 0
        guard Date().timeIntervalSince1970 - last <= gap else { return nil }
        return Date(timeIntervalSince1970: start)
    }
}
