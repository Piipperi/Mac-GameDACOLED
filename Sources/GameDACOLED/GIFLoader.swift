import Foundation
import ImageIO

enum GIFLoader {
    static func loadFrames(from url: URL) throws -> [GIFFrame] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw AppError("Unable to open GIF at \(url.path).")
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw AppError("The selected GIF contained no frames.")
        }

        return try (0 ..< frameCount).map { index in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                throw AppError("Unable to decode GIF frame \(index).")
            }

            let rendered = try ImageRenderer.renderToScreen(image)
            let duration = frameDuration(source: source, index: index)
            return GIFFrame(image: rendered, duration: duration)
        }
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }

        if let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
            return unclamped
        }

        if let delay = gifProperties[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
            return delay
        }

        return 0.1
    }
}
