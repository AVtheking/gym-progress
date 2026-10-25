import AVFoundation
import UIKit

enum TimelapseExporter {
    struct Frame {
        let fileName: String
        let date: Date
        let scale: Double
        let offsetX: Double
        let offsetY: Double
    }

    static func export(_ frames: [Frame]) async throws -> URL {
        let size = CGSize(width: 1080, height: 1440)
        let url = URL.temporaryDirectory.appending(path: "progress-timelapse.mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 7, timescale: 10)
        for (index, frame) in frames.enumerated() {
            guard let buffer = pixelBuffer(for: frame, size: size, pool: adaptor.pixelBufferPool) else { continue }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            adaptor.append(buffer, withPresentationTime: CMTimeMultiply(frameDuration, multiplier: Int32(index)))
        }
        input.markAsFinished()
        // Ending one frame later keeps the last photo on screen for a full beat.
        writer.endSession(atSourceTime: CMTimeMultiply(frameDuration, multiplier: Int32(frames.count)))
        await writer.finishWriting()
        if let error = writer.error { throw error }
        return url
    }

    private static func pixelBuffer(for frame: Frame, size: CGSize, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool, let image = PhotoStore.thumbnail(named: frame.fileName, maxPixel: 1600) else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        // UIKit drawing expects a top-left origin.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        // Same math as AlignedPhoto: aspect fill, then scale and offset from the center.
        let fill = max(size.width / image.size.width, size.height / image.size.height) * frame.scale
        let drawSize = CGSize(width: image.size.width * fill, height: image.size.height * fill)
        image.draw(in: CGRect(
            x: (size.width - drawSize.width) / 2 + frame.offsetX * size.width,
            y: (size.height - drawSize.height) / 2 + frame.offsetY * size.height,
            width: drawSize.width,
            height: drawSize.height
        ))

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 8
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
        (frame.date.formatted(.dateTime.month(.wide).year()) as NSString).draw(
            at: CGPoint(x: 48, y: size.height - 120),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.white,
                .shadow: shadow,
            ]
        )
        return buffer
    }
}
