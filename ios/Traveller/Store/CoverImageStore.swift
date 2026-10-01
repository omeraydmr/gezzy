import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Seyahat kapak fotoğraflarını uygulama klasöründe saklar; küçültülmüş görüntüyü ve
/// kartları renklendirmek için baskın rengini önbellekte tutar.
@MainActor
final class CoverImageStore {
    static let shared = CoverImageStore()
    /// Harcama makbuzları için ayrı klasör.
    static let receipts = CoverImageStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Receipts", isDirectory: true))

    private let directory: URL
    private let images = NSCache<NSString, UIImage>()
    private var colors: [String: Color] = [:]
    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    init(directory: URL = CoverImageStore.defaultDirectory) {
        self.directory = directory
        images.countLimit = 24
    }

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers", isDirectory: true)
    }

    /// Ham görüntü verisini en fazla 1400 pt kenarlı JPEG olarak kaydeder ve dosya adını döndürür.
    func save(_ data: Data) throws -> String {
        guard let image = UIImage(data: data) else { throw CoverError.unreadableImage }
        let resized = Self.resized(image, maxDimension: 1400)
        guard let jpeg = resized.jpegData(compressionQuality: 0.82) else { throw CoverError.unreadableImage }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        try jpeg.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        images.setObject(resized, forKey: name as NSString)
        return name
    }

    func image(named name: String) -> UIImage? {
        if let cached = images.object(forKey: name as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(name).path) else { return nil }
        images.setObject(image, forKey: name as NSString)
        return image
    }

    func delete(named name: String) {
        images.removeObject(forKey: name as NSString)
        colors[name] = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    /// Fotoğrafın ortalama renginden, kart üzerinde okunabilir kalacak şekilde doygunlaştırılmış bir ton.
    func dominantColor(named name: String) -> Color? {
        if let cached = colors[name] { return cached }
        guard let image = image(named: name), let input = CIImage(image: image) else { return nil }

        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        let average = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let vivid = UIColor(hue: hue, saturation: min(1, max(0.45, saturation * 1.6)),
                            brightness: min(0.85, max(0.55, brightness)), alpha: 1)
        let color = Color(uiColor: vivid)
        colors[name] = color
        return color
    }

    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return image }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    enum CoverError: LocalizedError {
        case unreadableImage

        var errorDescription: String? { "Fotoğraf okunamadı." }
    }
}
