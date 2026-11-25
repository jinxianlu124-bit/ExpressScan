# ExpressScan iOS 版（SwiftUI 原生）

Android 版（Kotlin + Compose）的 iOS 对应实现，功能一一对应：半屏连续扫码、会话式记录、历史永久保留、腾讯文档上传、条码生成。

## 一、环境要求

| 项目 | 要求 |
|---|---|
| 开发机 | **macOS + Xcode 15 以上**（Windows 无法编译 iOS） |
| 最低系统 | iOS 17.0（用了 SwiftData；如需支持 iOS 16 请改用 Core Data） |
| 设备 | iPhone（相机扫码需真机，模拟器无相机） |
| 账号 | 免费 Apple ID 可真机调试（签名 7 天有效）；99 美元/年开发者账号可 TestFlight / 上架 |

## 二、如何运行

1. 把整个 `ExpressScanIOS` 文件夹拷贝到 Mac（可用 U 盘 / 网盘 / Git）。
2. 双击 `ExpressScan.xcodeproj` 用 Xcode 打开。
3. 左侧选中 `ExpressScan` 工程 → **Signing & Capabilities**：
   - 勾选 `Automatically manage signing`
   - Team 选择你的 Apple ID（Personal Team 即可）
   - 若提示 Bundle ID 冲突，把 `com.expressscan.ios` 改成自己的，例如 `com.yourname.expressscan`
4. 用数据线连接 iPhone，顶部设备选择你的手机（首次需在 iPhone「设置 → 通用 → VPN与设备管理」信任开发者）。
5. `Cmd + R` 运行。首次运行时 iPhone 会弹相机权限，点允许。

> 免费 Apple ID 签名的 App **7 天后失效**，失效后需重新连电脑 `Cmd + R` 装一次（数据不会丢）。

## 三、功能说明（与 Android 版一致）

- **扫码页**：上半屏相机预览（约 45%），支持 CODE128 / CODE39 / QR / EAN / PDF417 等；批量模式连续录入，2 秒内同码自动去重，识别有震动反馈。
- **记录页**：
  - **本次记录**：只显示当前扫码会话。连续扫码间隔不超 **5 分钟**算一次记录；超过 5 分钟没扫码、或**关闭 App 重新打开**，本次记录自动结束并归入历史，记录页不再显示。
  - **全部历史**：完整数据永久保留，可按运单号/制式搜索。
  - 底部操作栏：全选 / 复制 / 删除（删除有二次确认）；右上角上传腾讯文档。
- **上传腾讯文档**：首次创建智能表，之后**追加到同一份表格**不再重复新建；三头鉴权（Access-Token / Client-Id / Open-Id）自动从 JWT 解析。内置 Token 约 **2026-11-23 过期**，过期后点「修改 Token」粘贴新 Token 即可。
- **生成页**：把运单号生成 CODE128 条码图片，可存相册。
- **更新检查**：启动时拉取云端 `update.json`，发现新版弹窗引导去下载页。**注意 iOS 不能像 Android 那样下载安装包静默安装**，如需 TestFlight 分发，把 `UpdateChecker.swift` 里的 `downloadPage` 换成 TestFlight 链接即可。

## 四、目录结构

```
ExpressScanIOS/
├─ ExpressScan.xcodeproj/            # Xcode 工程
└─ ExpressScan/
   ├─ App/          ExpressScanApp.swift（SwiftData 容器 + 冷启动重置会话）
   │                ContentView.swift（扫码/记录/生成 三标签 + 更新检查）
   ├─ Data/         ScanRecord.swift（数据模型）
   │                ScanSession.swift（5 分钟 / 冷启动 会话分界）
   ├─ Camera/       CameraController.swift（AVFoundation 条码识别）
   │                CameraPreview.swift（预览层）
   ├─ UI/           ScanView / RecordsView / UploadSheet / GenerateView
   ├─ Network/      TencentDocsUploader.swift（腾讯文档智能表四步链路）
   │                UpdateChecker.swift（版本检查）
   ├─ Resources/    Assets.xcassets/AppIcon.appiconset（奶牛图标）
   └─ Info.plist    相机/相册权限说明
```

## 五、如果 Xcode 打不开工程

极少数情况下手写工程文件可能与环境不兼容，可这样兜底：

1. Xcode → File → New → Project → iOS → App
2. Product Name 填 `ExpressScan`，Interface 选 **SwiftUI**，Language 选 **Swift**
3. 删掉自动生成的 `ContentView.swift`，把本目录 `App/`、`Data/`、`Camera/`、`UI/`、`Network/` 里的 `.swift` 文件全部拖进工程（勾选 Copy items）
4. 把 `Resources/Assets.xcassets` 覆盖到工程里，`Info.plist` 补充相机权限描述：`NSCameraUsageDescription`
5. 把 `ExpressScanApp.swift` 的 `@main` 保留，删除模板里的 `App` 结构体

## 六、已知说明

- 本工程在 Windows 上生成，**未在 Xcode 中编译验证**，首次打开如有编译提示按 Xcode 的 Fix 处理即可（通常是签名或部署版本）。
- iOS 版版本号独立于 Android 版（`UpdateChecker.localVersionCode = 1`）。
- 数据存储用 SwiftData，删除 App 会清空历史；重要数据建议及时上传到腾讯文档。
