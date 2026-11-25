import CoreImage
import UIKit

/// 一次打印任务的上下文（对应安卓 PrintSpec 里渲染需要的字段）
struct PrintSpec {
    var code: String = ""
    var packageSize: String = ""
    var serial: String = "0001"
    var time: Date = Date()
}

/// 标签渲染器：把模板画成 203dpi 的 1:1 位图，再交给 CPCL/TSPL 打包。
/// 与安卓端 LabelRenderer 同一套思路——全部在手机端画成位图，
/// 不依赖打印机字库，所以中文不会乱码、预览就是实打。
enum LabelRenderer {

    /// 203dpi 打印头：每毫米 8 点
    static let dotsPerMm: CGFloat = 8

    /// 打印头有效宽度：汉印 HM-A300 最大 72mm（576 点）
    static let maxWidthDots = 576

    // MARK: - 渲染

    static func render(_ template: LabelTemplate, spec: PrintSpec) -> UIImage {
        let rawW = max(Int(CGFloat(template.widthMm) * dotsPerMm), 64)
        let rawH = max(Int(CGFloat(template.heightMm) * dotsPerMm), 64)
        // 行宽按字节对齐（8 点），否则打包时最右几列会丢
        let width = min(((rawW + 7) / 8) * 8, maxWidthDots)
        let height = rawH

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)

        return renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            cg.setFillColor(UIColor.black.cgColor)

            // 纸宽超过打印头时整体等比缩小，宁可小也不能裁掉右侧
            let scale = CGFloat(width) / CGFloat(rawW)
            if scale < 1 { cg.scaleBy(x: scale, y: scale) }

            for element in template.elements {
                draw(element, in: cg, spec: spec)
            }
        }
    }

    /// 预览图：按屏幕宽度缩放，只用于界面显示
    static func preview(_ template: LabelTemplate, spec: PrintSpec, maxWidth: CGFloat = 900) -> UIImage {
        let full = render(template, spec: spec)
        let ratio = maxWidth / full.size.width
        if ratio >= 1 { return full }
        let size = CGSize(width: full.size.width * ratio, height: full.size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            full.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - 元素绘制

    private static func draw(_ e: LabelElement, in cg: CGContext, spec: PrintSpec) {
        let x = CGFloat(e.xMm) * dotsPerMm
        let y = CGFloat(e.yMm) * dotsPerMm
        let w = max(CGFloat(e.wMm) * dotsPerMm, 4)
        let h = max(CGFloat(e.hMm) * dotsPerMm, 4)

        cg.saveGState()
        if e.rotation != 0 {
            cg.translateBy(x: x + w / 2, y: y + h / 2)
            cg.rotate(by: CGFloat(e.rotation) * .pi / 180)
            cg.translateBy(x: -(x + w / 2), y: -(y + h / 2))
        }

        switch e.type {
        case .CODE_BARCODE:
            // 一维码：横向按整数模块宽画竖条、纵向铺满。不能等比缩放，
            // 否则长条码会被高度卡住缩成一小条（安卓端踩过的坑）。
            drawBarcode1D(e.resolve(spec), x: x, y: y, w: w, h: h, in: cg)
        case .CODE_QR:
            drawQRCode(e.resolve(spec), x: x, y: y, w: w, h: h, in: cg)
        case .CODE_TEXT, .SIZE_TEXT, .DATE_TEXT, .CUSTOM_TEXT, .SERIAL_TEXT:
            drawText(e, text: e.resolve(spec), x: x, y: y, w: w, h: h, in: cg)
        case .LINE:
            if w >= h {
                cg.fill(CGRect(x: x, y: y, width: w, height: max(2, h)))
            } else {
                cg.fill(CGRect(x: x, y: y, width: max(2, w), height: h))
            }
        case .RECT:
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(max(2, min(w, h) * 0.06))
            cg.stroke(CGRect(x: x, y: y, width: w, height: h))
        case .IMAGE:
            drawImage(e, x: x, y: y, w: w, h: h, in: cg)
        }

        cg.restoreGState()
    }

    // MARK: 文字

    private static func drawText(_ e: LabelElement, text: String, x: CGFloat, y: CGFloat,
                                 w: CGFloat, h: CGFloat, in cg: CGContext) {
        guard !text.isEmpty else { return }
        let lines = text.components(separatedBy: "\n")

        var size = max(CGFloat(e.fontMm) * dotsPerMm, 8)
        var font = e.bold ? UIFont.systemFont(ofSize: size, weight: .bold) : UIFont.systemFont(ofSize: size)

        // 长文字自动缩字号，保证不打出边界
        while size > 8 {
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let fits = lines.allSatisfy { ($0 as NSString).size(withAttributes: attrs).width <= w }
            if fits { break }
            size -= 1
            font = e.bold ? UIFont.systemFont(ofSize: size, weight: .bold) : UIFont.systemFont(ofSize: size)
        }

        let para = NSMutableParagraphStyle()
        para.alignment = e.align == .LEFT ? .left : (e.align == .CENTER ? .center : .right)
        para.lineBreakMode = .byClipping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: para,
        ]

        let lineH = size * 1.18
        let blockH = lineH * CGFloat(lines.count)
        var top = y + (h - blockH) / 2

        UIGraphicsPushContext(cg)
        for line in lines {
            (line as NSString).draw(in: CGRect(x: x, y: top, width: w, height: lineH), withAttributes: attrs)
            top += lineH
        }
        UIGraphicsPopContext()
    }

    // MARK: 一维条码

    private static func drawBarcode1D(_ text: String, x: CGFloat, y: CGFloat,
                                      w: CGFloat, h: CGFloat, in cg: CGContext) {
        guard let image = code128Image(text) else { return }
        let bits = columnBits(image)
        guard !bits.isEmpty else { return }

        // 去掉两端静区（白边由区域自己留）
        var start = 0
        var end = bits.count - 1
        while start < bits.count && !bits[start] { start += 1 }
        while end > start && !bits[end] { end -= 1 }
        guard start <= end else { return }

        let modules = end - start + 1
        var unit = (w / CGFloat(modules)).rounded(.down)
        if unit < 1 { unit = w / CGFloat(modules) } // 单号太长，只能压缩
        let left = x + (w - CGFloat(modules) * unit) / 2

        var i = start
        while i <= end {
            if bits[i] {
                var j = i
                while j <= end && bits[j] { j += 1 }
                cg.fill(CGRect(x: left + CGFloat(i - start) * unit, y: y,
                               width: CGFloat(j - i) * unit, height: h))
                i = j
            } else {
                i += 1
            }
        }
    }

    /// Code128 编码图：只取一行像素判断黑白，再自己按矩形重画（边缘绝对锐利）
    private static func code128Image(_ text: String) -> CGImage? {
        guard let message = text.data(using: .ascii), !message.isEmpty else { return nil }
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
        filter.setValue(message, forKey: "inputMessage")
        filter.setValue(0, forKey: "inputQuietSpace")
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: output.extent)
    }

    private static func columnBits(_ image: CGImage) -> [Bool] {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return [] }

        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let row = h / 2
        var bits = [Bool](repeating: false, count: w)
        for cx in 0..<w {
            let idx = (row * w + cx) * 4
            let lum = (Int(pixels[idx]) * 299 + Int(pixels[idx + 1]) * 587 + Int(pixels[idx + 2]) * 114) / 1000
            bits[cx] = lum < 128
        }
        return bits
    }

    // MARK: 二维码

    private static func drawQRCode(_ text: String, x: CGFloat, y: CGFloat,
                                   w: CGFloat, h: CGFloat, in cg: CGContext) {
        guard let image = qrImage(text) else { return }
        let grid = pixelGrid(image)
        let mw = grid.width
        let mh = grid.height
        guard mw > 0, mh > 0 else { return }

        // 整数倍放大，每个模块落在整数像素上，扫描器才读得准
        var k = (min(w / CGFloat(mw), h / CGFloat(mh))).rounded(.down)
        if k < 1 { k = min(w / CGFloat(mw), h / CGFloat(mh)) }
        let left = x + (w - CGFloat(mw) * k) / 2
        let top = y + (h - CGFloat(mh) * k) / 2

        for r in 0..<mh {
            var c = 0
            while c < mw {
                if grid.bits[r * mw + c] {
                    var c2 = c
                    while c2 < mw && grid.bits[r * mw + c2] { c2 += 1 }
                    cg.fill(CGRect(x: left + CGFloat(c) * k, y: top + CGFloat(r) * k,
                                   width: CGFloat(c2 - c) * k, height: k))
                    c = c2
                } else {
                    c += 1
                }
            }
        }
    }

    private static func qrImage(_ text: String) -> CGImage? {
        guard let message = text.data(using: .utf8), !message.isEmpty else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(message, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: output.extent)
    }

    private static func pixelGrid(_ image: CGImage) -> (width: Int, height: Int, bits: [Bool]) {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return (0, 0, []) }

        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0, []) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var bits = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            let idx = i * 4
            let lum = (Int(pixels[idx]) * 299 + Int(pixels[idx + 1]) * 587 + Int(pixels[idx + 2]) * 114) / 1000
            bits[i] = lum < 128
        }
        return (w, h, bits)
    }

    // MARK: 图片

    private static func drawImage(_ e: LabelElement, x: CGFloat, y: CGFloat,
                                  w: CGFloat, h: CGFloat, in cg: CGContext) {
        // 安卓端的图片是绝对路径，iOS 上没有意义；这里只认 iOS 自己的文件路径
        guard !e.imagePath.isEmpty,
              let image = UIImage(contentsOfFile: e.imagePath) else { return }
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0 else { return }
        let scale = min(w / iw, h / ih)
        let dw = iw * scale
        let dh = ih * scale
        let rect = CGRect(x: x + (w - dw) / 2, y: y + (h - dh) / 2, width: dw, height: dh)

        UIGraphicsPushContext(cg)
        UIColor.white.setFill()
        UIBezierPath(rect: rect).fill()
        image.draw(in: rect)
        UIGraphicsPopContext()
    }

    // MARK: - 二值化

    /// 整张图按亮度二值化并打包成 1-bit 行数据（MSB 在前），
    /// 与 CPCL 的 EG 指令、TSPL 的 BITMAP 指令要求的字节序一致。
    static func monoBytes(_ image: UIImage, density: Int) -> (bytes: [UInt8], width: Int, height: Int) {
        guard let cgImage = image.cgImage else { return ([], 0, 0) }
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return ([], 0, 0) }

        // 阈值随浓度变化：字浅、条码扫不出就调高，把灰边也打成黑点
        let level = 116 + min(max(density, 1), 15) * 8

        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return ([], 0, 0) }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        let rowBytes = (w + 7) / 8
        var out = [UInt8](repeating: 0, count: rowBytes * h)

        for y in 0..<h {
            let base = y * rowBytes
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let lum = (Int(pixels[idx]) * 299 + Int(pixels[idx + 1]) * 587 + Int(pixels[idx + 2]) * 114) / 1000
                if lum < level {
                    out[base + (x >> 3)] |= UInt8(0x80 >> UInt8(x & 7))
                }
            }
        }
        return (out, w, h)
    }
}
