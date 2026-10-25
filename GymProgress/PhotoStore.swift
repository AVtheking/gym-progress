import ImageIO
import UIKit

enum PhotoStore {
    static let directory: URL = {
        let url = URL.applicationSupportDirectory.appending(path: "Photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let cache = NSCache<NSString, UIImage>()

    static func url(for fileName: String) -> URL {
        directory.appending(path: fileName)
    }

    /// Re-encoding downscales, bakes in orientation and drops metadata such as location.
    static func save(_ data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = downsampled(source, maxPixel: 2400),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.88)
        else { throw CocoaError(.fileReadCorruptFile) }
        let fileName = UUID().uuidString + ".jpg"
        try jpeg.write(to: url(for: fileName), options: [.atomic, .completeFileProtection])
        return fileName
    }

    static func thumbnail(named fileName: String, maxPixel: Int) -> UIImage? {
        let key = "\(fileName)-\(maxPixel)" as NSString
        
        if let cached = cache.object(forKey: key) { return cached }
        
        guard let source = CGImageSourceCreateWithURL(url(for: fileName) as CFURL, nil),
              let image = downsampled(source, maxPixel: maxPixel)
        
        else { return nil }
        let result = UIImage(cgImage: image)
        cache.setObject(result, forKey: key)
        return result
    }

    static func preview(of data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = downsampled(source, maxPixel: maxPixel)
        else { return nil }
        return UIImage(cgImage: image)
    }

    static func captureDate(of data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let raw = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }

    static func delete(named fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    private static func downsampled(_ source: CGImageSource, maxPixel: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }
}
