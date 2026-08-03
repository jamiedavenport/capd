import CoreGraphics
import Foundation
import ImageIO

/// Decides whether favicon artwork is too dark to read on the app's near-black chip.
/// ImageIO/CoreGraphics rather than NSImage keeps AppKit out of CapKit.
public enum FaviconLuminance {
    /// True when the artwork needs a light chip behind it. Undecodable or
    /// effectively-empty images return false, keeping the default chip.
    public static func needsLightBacking(pngData: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return false
        }
        return needsLightBacking(image)
    }

    /// Dark artwork wants the light chip unless it brought its own opaque light
    /// background. Luminance is alpha-weighted so anti-aliased edges and ghosted
    /// icons are judged by their ink color, not their composite against nothing.
    public static func needsLightBacking(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return false }
        let bytesPerRow = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        var alphaSum = 0.0
        var luminanceSum = 0.0
        var borderAlphaSum = 0.0
        var borderLuminanceSum = 0.0
        for y in 0..<height {
            let row = y * bytesPerRow
            let borderRow = y < 2 || y >= height - 2
            for x in 0..<width {
                let pixel = row + x * 4
                let red = Double(pixels[pixel]) / 255
                let green = Double(pixels[pixel + 1]) / 255
                let blue = Double(pixels[pixel + 2]) / 255
                let alpha = Double(pixels[pixel + 3]) / 255
                // Premultiplied channels mean Σluminance / Σalpha is already the
                // alpha-weighted mean of the un-premultiplied color.
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                alphaSum += alpha
                luminanceSum += luminance
                if borderRow || x < 2 || x >= width - 2 {
                    borderAlphaSum += alpha
                    borderLuminanceSum += luminance
                }
            }
        }

        let coverage = alphaSum / Double(width * height)
        guard coverage >= FaviconPolicy.minimumAnalyzableCoverage else { return false }
        guard luminanceSum / alphaSum < FaviconPolicy.darkArtworkLuminance else { return false }
        let hasOwnLightBackground =
            coverage >= FaviconPolicy.opaqueBackgroundCoverage
            && borderAlphaSum > 0
            && borderLuminanceSum / borderAlphaSum >= FaviconPolicy.lightBackgroundLuminance
        return !hasOwnLightBackground
    }
}
