import CoreImage.CIFilterBuiltins
import SwiftUI

/// 生成页：把运单号转成 CODE128 条码图片，可保存到相册。
struct GenerateView: View {
    @State private var text = ""
    @State private var image: UIImage?
    @State private var saved = false

    private let context = CIContext()

    var body: some View {
        VStack(spacing: 16) {
            TextField("输入运单号 / 内容", text: $text)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            Button("生成条码") { generate() }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(height: 120)
                    .padding(.horizontal, 24)

                Button(saved ? "已保存到相册" : "保存到相册") { save(image) }
                    .buttonStyle(.bordered)
            }

            Spacer()
        }
        .navigationTitle("生成条码")
    }

    private func generate() {
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage else { return }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return }
        image = UIImage(cgImage: cgImage)
        saved = false
    }

    private func save(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        saved = true
    }
}
