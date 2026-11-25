import Foundation
import UIKit

/// 标签机指令协议
enum PrinterProtocol: String, CaseIterable, Identifiable {
    /// 汉印 HM-A300 等便携标签机的原生指令集
    case cpcl
    /// 佳博 / 汉印桌面机（TSPL/TSC）
    case tspl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpcl: return "CPCL（汉印 A300 等便携机）"
        case .tspl: return "TSPL（佳博 / 桌面标签机）"
        }
    }

    var hint: String {
        switch self {
        case .cpcl: return "汉印 HM-A300 用这一档，默认值，不用改"
        case .tspl: return "出图偏小或乱码时换这一档试试"
        }
    }
}

/// 指令打包：把 1:1 位图变成打印机认的字节流。
/// 这两个协议都是「整页位图」模型，手机端画好，打印机只负责点阵输出，所以不会乱码。
enum LabelCommandBuilder {

    static func build(image: UIImage,
                      proto: PrinterProtocol,
                      density: Int,
                      speed: Int,
                      copies: Int,
                      gapMm: Int) -> Data {
        let mono = LabelRenderer.monoBytes(image, density: density)
        guard mono.width > 0, mono.height > 0 else { return Data() }

        switch proto {
        case .cpcl:
            return cpcl(bytes: mono.bytes, width: mono.width, height: mono.height, copies: copies)
        case .tspl:
            return tspl(bytes: mono.bytes, width: mono.width, height: mono.height,
                        density: density, speed: speed, gapMm: gapMm)
        }
    }

    // MARK: CPCL

    /// `! 0 200 200 <高> <份数>` 开作业 + `PAGE-WIDTH` + `EG` 十六进制位图 + `FORM` + `PRINT`。
    /// EG 数据：每字节写成两个 ASCII 字符，0=白 1=黑、MSB 在前、自上而下逐行。
    private static func cpcl(bytes: [UInt8], width: Int, height: Int, copies: Int) -> Data {
        let rowBytes = width / 8
        var data = Data()

        func line(_ s: String) {
            data.append(contentsOf: Array(s.utf8))
            data.append(0x0D)
            data.append(0x0A)
        }

        line("! 0 200 200 \(height) \(max(copies, 1))")
        line("PAGE-WIDTH \(width)")
        data.append(contentsOf: Array("EG \(rowBytes) \(height) 0 0 ".utf8))

        let hexChars = Array("0123456789ABCDEF".utf8)
        var hex = [UInt8]()
        hex.reserveCapacity(bytes.count * 2)
        for b in bytes {
            hex.append(hexChars[Int(b >> 4)])
            hex.append(hexChars[Int(b & 0x0F)])
        }
        data.append(contentsOf: hex)
        data.append(0x0D)
        data.append(0x0A)

        line("FORM")
        line("PRINT")
        return data
    }

    // MARK: TSPL

    private static func tspl(bytes: [UInt8], width: Int, height: Int,
                             density: Int, speed: Int, gapMm: Int) -> Data {
        let rowBytes = width / 8
        var data = Data()

        func line(_ s: String) {
            data.append(contentsOf: Array(s.utf8))
            data.append(0x0D)
            data.append(0x0A)
        }

        line("SIZE \(width) dot,\(height) dot")
        line("GAP \(max(gapMm, 0)) mm,0")
        line("OFFSET 0 mm")
        line("SPEED \(min(max(speed, 1), 4))")
        line("DENSITY \(min(max(density - 1, 0), 15))")
        line("DIRECTION 1,0")
        line("REFERENCE 0,0")
        line("CLS")
        data.append(contentsOf: Array("BITMAP 0,0,\(rowBytes),\(height),0,".utf8))
        data.append(contentsOf: bytes)
        data.append(0x0D)
        data.append(0x0A)
        line("PRINT 1,1")
        return data
    }
}
