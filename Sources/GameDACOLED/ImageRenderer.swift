import AppKit
import CoreGraphics
import Foundation
import ImageIO

enum ImageRenderer {
    static let width = 128
    static let height = 52
    static let bitmapLength = (width * height + 7) / 8

    static func blankBitmap() -> [UInt8] {
        Array(repeating: 0, count: bitmapLength)
    }

    static func blankCGImage() -> CGImage {
        render { _, _ in }
    }

    static func clockImage(date: Date, showsDate: Bool) -> CGImage {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE d MMM"

        let timeString = timeFormatter.string(from: date)
        let dateString = dateFormatter.string(from: date).uppercased()

        return render { _, _ in
            let background = NSRect(x: 0, y: 0, width: width, height: height)
            NSColor.black.setFill()
            background.fill()

            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: showsDate ? 25 : 30, weight: .bold),
                .foregroundColor: NSColor.white
            ]

            let timeSize = timeString.size(withAttributes: timeAttributes)
            let timeY: CGFloat = showsDate ? 10 : 13
            let timeOrigin = NSPoint(x: (CGFloat(width) - timeSize.width) / 2, y: timeY)
            timeString.draw(at: timeOrigin, withAttributes: timeAttributes)

            if showsDate {
                let dateSize = dateString.size(withAttributes: dateAttributes)
                let dateOrigin = NSPoint(x: (CGFloat(width) - dateSize.width) / 2, y: 37)
                dateString.draw(at: dateOrigin, withAttributes: dateAttributes)
            }
        }
    }

    static func systemStatsImage(
        snapshot: SystemSnapshot,
        showsDate: Bool,
        usesUnixCPUPercent: Bool,
        hidesMetricPercentSymbols: Bool
    ) -> CGImage {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE d MMM"

        let timeString = timeFormatter.string(from: snapshot.timestamp)
        let dateString = dateFormatter.string(from: snapshot.timestamp).uppercased()
        let rows = [
            ("CPU", hidesMetricPercentSymbols ? "\(snapshot.cpuPercent)" : "\(snapshot.cpuPercent)%"),
            ("GPU", snapshot.gpuPercent.map { hidesMetricPercentSymbols ? "\($0)" : "\($0)%" } ?? "--"),
            ("RAM", hidesMetricPercentSymbols ? "\(snapshot.ramPercent)" : "\(snapshot.ramPercent)%")
        ]

        return render { _, _ in
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()

            let dividerX: CGFloat = 62
            let leftWidth = dividerX - 4
            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: showsDate ? 23 : 25, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let compactValueAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor.white
            ]

            let timeSize = timeString.size(withAttributes: timeAttributes)
            let timeOrigin = NSPoint(x: max(1, (leftWidth - timeSize.width) / 2), y: showsDate ? 18 : 13)
            timeString.draw(at: timeOrigin, withAttributes: timeAttributes)

            if showsDate {
                let dateSize = dateString.size(withAttributes: dateAttributes)
                let dateOrigin = NSPoint(x: max(2, (leftWidth - dateSize.width) / 2), y: 7)
                dateString.draw(at: dateOrigin, withAttributes: dateAttributes)
            }

            let path = NSBezierPath()
            path.move(to: NSPoint(x: dividerX, y: 5))
            path.line(to: NSPoint(x: dividerX, y: CGFloat(height - 5)))
            NSColor.white.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 1
            path.stroke()

            let startX: CGFloat = 78
            let startY: CGFloat = 36
            let rowGap: CGFloat = 13.5

            for (index, row) in rows.enumerated() {
                let y = startY - CGFloat(index) * rowGap
                row.0.draw(at: NSPoint(x: startX, y: y), withAttributes: labelAttributes)
                let chosenAttributes = row.1.count >= 5 ? compactValueAttributes : valueAttributes
                let valueSize = row.1.size(withAttributes: chosenAttributes)
                row.1.draw(
                    at: NSPoint(x: CGFloat(width) - valueSize.width - 3, y: y - 1),
                    withAttributes: chosenAttributes
                )
            }
        }
    }

    static func audioVisualizerImage(
        levels: [Float],
        metrics: SystemSnapshot?,
        hidesPercentSymbols: Bool,
        usesUnixCPUPercent: Bool
    ) -> CGImage {
        render { _, _ in
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()

            let barCount = max(levels.count, 1)
            let spacing: CGFloat = 2
            let totalSpacing = CGFloat(barCount - 1) * spacing
            let availableWidth = CGFloat(width) - 8 - totalSpacing
            let barWidth = max(2, floor(availableWidth / CGFloat(barCount)))
            let metricsHeight: CGFloat = metrics == nil ? 0 : 9
            let baseline: CGFloat = metrics == nil ? 1 : 2
            let topPadding: CGFloat = metrics == nil ? 1 : 2
            let maxBarHeight = CGFloat(height) - baseline - topPadding - metricsHeight

            if let metrics {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .semibold),
                    .foregroundColor: NSColor.white
                ]
                let values = [
                    formatMetric(metrics.cpuPercent, hidesPercentSymbols: hidesPercentSymbols, forcePercentSymbol: !hidesPercentSymbols),
                    formatMetric(metrics.gpuPercent ?? 0, hidesPercentSymbols: hidesPercentSymbols),
                    formatMetric(metrics.ramPercent, hidesPercentSymbols: hidesPercentSymbols)
                ]
                let topY = CGFloat(height) - 9
                let cellWidth = CGFloat(width) / 3

                for (index, value) in values.enumerated() {
                    let valueSize = value.size(withAttributes: attributes)
                    let originX = CGFloat(index) * cellWidth + (cellWidth - valueSize.width) / 2
                    value.draw(at: NSPoint(x: originX, y: topY), withAttributes: attributes)
                }
            }

            for (index, level) in levels.enumerated() {
                let clamped = CGFloat(max(0, min(level, 1)))
                let barHeight = max(2, round(clamped * maxBarHeight))
                let x = 4 + CGFloat(index) * (barWidth + spacing)
                let rect = NSRect(x: x, y: baseline, width: barWidth, height: barHeight)

                let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
                NSColor.white.setFill()
                path.fill()
            }
        }
    }

    private static func formatMetric(_ value: Int, hidesPercentSymbols: Bool, forcePercentSymbol: Bool = false) -> String {
        if forcePercentSymbol {
            return "\(value)%"
        }
        return hidesPercentSymbols ? "\(value)" : "\(value)%"
    }

    static func loadFirstFrame(from url: URL) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AppError("Unable to decode image at \(url.path).")
        }

        return image
    }

    static func renderToScreen(
        _ image: CGImage,
        contrast: Double = 1,
        zoom: Double = 1,
        inverted: Bool = false
    ) throws -> CGImage {
        renderScaled(image, contrast: contrast, zoom: zoom, inverted: inverted)
    }

    static func previewImage(from image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: width * 4, height: height * 4))
    }

    static func packBitmap(
        from image: CGImage,
        ditheringEnabled: Bool = false,
        contrast: Double = 1,
        zoom: Double = 1,
        inverted: Bool = false
    ) -> [UInt8] {
        let rendered = renderScaled(image, contrast: contrast, zoom: zoom, inverted: inverted)
        return packBitmap(fromRendered: rendered, ditheringEnabled: ditheringEnabled)
    }

    static func packBitmap(fromRendered rendered: CGImage, ditheringEnabled: Bool = false) -> [UInt8] {
        guard let pixelData = rendered.dataProvider?.data else {
            return blankBitmap()
        }

        let bytes = CFDataGetBytePtr(pixelData)!
        var packed = blankBitmap()
        let bayer4x4: [Int] = [
            0, 8, 2, 10,
            12, 4, 14, 6,
            3, 11, 1, 9,
            15, 7, 13, 5
        ]

        for y in 0 ..< height {
            for x in 0 ..< width {
                let pixelIndex = (y * width + x) * 4
                let red = bytes[pixelIndex]
                let green = bytes[pixelIndex + 1]
                let blue = bytes[pixelIndex + 2]
                let luminance = Int(red) + Int(green) + Int(blue)
                let threshold: Int
                if ditheringEnabled {
                    let matrixIndex = (y % 4) * 4 + (x % 4)
                    threshold = 192 + bayer4x4[matrixIndex] * 12
                } else {
                    threshold = 384
                }

                if luminance >= threshold {
                    let bitIndex = y * width + x
                    packed[bitIndex / 8] |= 1 << (7 - (bitIndex % 8))
                }
            }
        }

        return packed
    }

    private static func renderScaled(
        _ image: CGImage,
        contrast: Double = 1,
        zoom: Double = 1,
        inverted: Bool = false
    ) -> CGImage {
        render { cgContext, size in
            cgContext.interpolationQuality = .high
            cgContext.setFillColor(NSColor.clear.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: size))

            let imageRect = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
            let targetRect = aspectFit(source: imageRect.size, target: size, zoom: zoom)
            cgContext.draw(image, in: targetRect)
            applyPostProcessing(to: cgContext, contrast: contrast, inverted: inverted)
        }
    }

    private static func aspectFit(source: CGSize, target: CGSize, zoom: Double = 1) -> CGRect {
        let scale = min(target.width / source.width, target.height / source.height) * max(zoom, 0.05)
        let scaledSize = CGSize(width: source.width * scale, height: source.height * scale)
        let origin = CGPoint(
            x: (target.width - scaledSize.width) / 2,
            y: (target.height - scaledSize.height) / 2
        )
        return CGRect(origin: origin, size: scaledSize)
    }

    private static func render(draw: (CGContext, CGSize) -> Void) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        draw(context, CGSize(width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()!
    }

    private static func applyPostProcessing(to context: CGContext, contrast: Double, inverted: Bool) {
        guard let data = context.data else {
            return
        }

        let clampedContrast = max(0, contrast)
        let bytes = data.assumingMemoryBound(to: UInt8.self.self)
        let pixelCount = width * height

        for index in 0 ..< pixelCount {
            let pixelOffset = index * 4
            let alpha = Double(bytes[pixelOffset + 3]) / 255
            if alpha <= 0.001 {
                bytes[pixelOffset] = 0
                bytes[pixelOffset + 1] = 0
                bytes[pixelOffset + 2] = 0
                continue
            }
            let red = Double(bytes[pixelOffset]) / 255
            let green = Double(bytes[pixelOffset + 1]) / 255
            let blue = Double(bytes[pixelOffset + 2]) / 255
            let luminance = max(0, min(1, 0.299 * red + 0.587 * green + 0.114 * blue))
            var adjusted = max(0, min(1, (luminance - 0.5) * clampedContrast + 0.5))
            if inverted {
                adjusted = 1 - adjusted
            }
            let value = UInt8((adjusted * 255).rounded())
            bytes[pixelOffset] = value
            bytes[pixelOffset + 1] = value
            bytes[pixelOffset + 2] = value
        }
    }
}
