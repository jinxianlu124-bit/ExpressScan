# ExpressScan iOS 版（SwiftUI 原生）

Android 版（Kotlin + Compose）的 iOS 对应实现。v2.0 起**补齐蓝牙打印**：
扫码 → 记录 → 打标签，完整闭环都在手机上完成。

## 一、v2.0 新增：蓝牙打印

| 能力 | 说明 |
|---|---|
| 连接打印机 | BLE（低功耗蓝牙）扫描 / 连接 / 自动重连，已连接过的打印机会记住 |
| 打印协议 | **CPCL**（汉印 HM-A300 等便携标签机，默认）与 **TSPL**（佳博 / 桌面标签机）两档 |
| 出票方式 | 整页 1:1 位图（203dpi，8 点/毫米），不依赖打印机字库 → 中文不乱码、预览即实打 |
| 模板 | 内置 3 套 + 支持导入模板 JSON（字段与安卓端 `label_templates.json` 完全一致） |
| 快速排版 | 没选模板时按输入内容自动排版：条码 + 单号 + 附加文字 |
| 扫码自动打印 | 打印页顶部开关，扫到新单号立即出票 |
| 条码 | Code128 一维码（按整数模块宽绘制，细条不糊）与 QR 二维码（整数倍放大） |
| 参数 | 浓度 1~15、速度 1~5、份数 1~99、标签纸 30×20 / 40×30 / 40×60 / 50×30 / 60×40 |

> 为什么 iOS 能打：汉印 HM-A300 官方规格是「蓝牙 3.0 + BLE 双模」，并明确提供 iOS SDK，
> 指令集就是 CPCL。iOS 上的经典蓝牙 SPP 只对 MFi 配件开放，但走 BLE 数据通道不受这个限制。

### 模板 JSON 格式

与安卓端同结构，可直接互用：

```json
[{
  "id": "t1",
  "name": "运单标签 40×30",
  "w": 40,
  "h": 30,
  "elements": [
    { "type": "CODE_BARCODE", "xMm": 2, "yMm": 2, "wMm": 36, "hMm": 13 },
    { "type": "CODE_TEXT", "xMm": 2, "yMm": 16, "wMm": 36, "hMm": 7, "fontMm": 4, "bold": true },
    { "type": "CUSTOM_TEXT", "text": "谢谢惠顾", "xMm": 2, "yMm": 24, "wMm": 36, "hMm": 4, "fontMm": 2.6 }
  ]
}]
```

字段说明：`type` 取 `CODE_BARCODE / CODE_QR / CODE_TEXT / SIZE_TEXT / DATE_TEXT / CUSTOM_TEXT / SERIAL_TEXT / LINE / RECT / IMAGE`；
`align` 取 `LEFT / CENTER / RIGHT`；`data.kind` 取 `FIXED / SERIAL / DATETIME`（不填按固定数据）。

**导入方式**：打印页 →「模板」→「从文件导入模板 JSON」。也可以把文件放进
「文件」App 里的 `我的 iPhone / 快递扫码` 文件夹（App 已开启文件共享）。

## 二、环境要求

| 项目 | 要求 |
|---|---|
| 开发机 | **macOS + Xcode 15 以上**（Windows 无法编译 iOS） |
| 最低系统 | iOS 17.0（用了 SwiftData） |
| 设备 | iPhone 真机（相机扫码 + 蓝牙打印都必须真机，模拟器没有这两样） |
| 账号 | 免费 Apple ID 可真机调试（签名 7 天有效）；99 美元/年开发者账号可 TestFlight / 上架 |

## 三、如何运行

1. 把整个 `ExpressScanIOS` 文件夹拷贝到 Mac。
2. 双击 `ExpressScan.xcodeproj` 用 Xcode 打开。
3. 左侧选中 `ExpressScan` 工程 → **Signing & Capabilities**：
   - 勾选 `Automatically manage signing`
   - Team 选择你的 Apple ID（Personal Team 即可）
   - 若提示 Bundle ID 冲突，把 `com.expressscan.ios` 改成自己的，例如 `com.yourname.expressscan`
4. 数据线连接 iPhone，顶部设备选择你的手机，`Cmd + R` 运行。
   首次运行需：设置 → 通用 → VPN与设备管理 → 信任开发者；iOS 16+ 还要在
   设置 → 隐私与安全性 → 打开「开发者模式」。
5. 打印机开机 → App「打印」页 → 点「连接」→ 选中打印机 → 打测试页确认走纸对位。

> 免费 Apple ID 签名的 App **7 天后失效**，失效后重连电脑 `Cmd + R` 装一次（数据不会丢）。

## 四、功能说明

- **扫码页**：上半屏相机预览，批量模式连续录入，2 秒内同码去重，识别有震动反馈；
  打印页开关打开时，扫到单号会自动出票。
- **记录页**：本次记录（5 分钟 / 冷启动切分）+ 全部历史，可按运单号/制式搜索，
  底部全选 / 复制 / 删除，右上角上传腾讯文档。
- **打印页**：顶部「扫码后自动打印」开关 → 打印机状态 → 当前模板 → 单号输入 →
  实时预览 → 底部份数与打印按钮；右上角是高级设置（协议 / 浓度 / 速度 / 测试页）。
- **生成页**：把运单号生成 Code128 条码图片，可存相册。
- **更新检查**：比对云端清单里的 `iosVersionCode`（iOS 有独立版本号，
  不会被安卓版本号误触发提示）。

## 五、目录结构

```
ExpressScanIOS/
├─ ExpressScan.xcodeproj/
└─ ExpressScan/
   ├─ App/          ExpressScanApp.swift（SwiftData 容器 + 冷启动重置会话）
   │                ContentView.swift（扫码/记录/打印/生成 四标签）
   ├─ Data/         ScanRecord / ScanSession
   ├─ Camera/       CameraController / CameraPreview（AVFoundation 条码识别）
   ├─ Printer/      LabelTemplate.swift      模板模型 + 模板库（JSON 与安卓通用）
   │                LabelRenderer.swift      203dpi 位图渲染（文字/条码/二维码/线框）
   │                LabelCommandBuilder.swift CPCL / TSPL 指令打包
   │                BLEPrinter.swift         CoreBluetooth 连接与分包发送
   │                PrinterStore.swift       打印参数持久化
   │                PrintService.swift       打印执行入口 + 快速排版（手动 / 扫码自动）
   ├─ UI/           ScanView / RecordsView / UploadSheet / GenerateView / PrintView
   ├─ Network/      TencentDocsUploader / UpdateChecker
   ├─ Resources/    Assets.xcassets
   └─ Info.plist    相机 / 蓝牙 / 相册权限，开启文件共享
```

## 六、如果 Xcode 打不开工程

1. Xcode → File → New → Project → iOS → App
2. Product Name 填 `ExpressScan`，Interface 选 **SwiftUI**，Language 选 **Swift**
3. 删掉自动生成的 `ContentView.swift`，把本目录 `App/`、`Data/`、`Camera/`、`Printer/`、
   `UI/`、`Network/` 里的 `.swift` 文件全部拖进工程（勾选 Copy items）
4. 覆盖 `Resources/Assets.xcassets`，并在 Info.plist 补：
   `NSCameraUsageDescription`、`NSBluetoothAlwaysUsageDescription`、`NSPhotoLibraryAddUsageDescription`
5. 保留 `ExpressScanApp.swift` 的 `@main`，删掉模板里的 `App` 结构体

## 七、已知说明

- 本工程在 Windows 上生成，**未在 Xcode 中实际编译验证**；如有编译提示，按 Xcode 的 Fix 处理
  （通常是签名、部署版本或 Info.plist 键），把报错发我即可修。
- iOS 端暂未移植：模板可视化编辑器、防扫错单号校验、记录按天分组。
  模板可以在安卓上设计好，把 JSON 导入 iOS 使用。
- 数据用 SwiftData 存储，删除 App 会清空历史；重要数据及时上传腾讯文档。
- 蓝牙分块大小按 `maximumWriteValueLength` 自适应（上限 480 字节），
  支持 withResponse 的通道走应答流控，避免大批量位图丢字节。
