import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CapKit

@Suite("FaviconLuminance")
struct FaviconLuminanceTests {
    @Test("A dark glyph on transparency needs the light chip")
    func darkGlyph() {
        let png = makePNG(glyph: CGColor(gray: 0, alpha: 1))
        #expect(FaviconLuminance.needsLightBacking(pngData: png))
    }

    @Test("A light glyph on transparency does not")
    func lightGlyph() {
        let png = makePNG(glyph: CGColor(gray: 1, alpha: 1))
        #expect(!FaviconLuminance.needsLightBacking(pngData: png))
    }

    @Test("A fully opaque dark plate needs the light chip")
    func opaqueDarkPlate() {
        let png = makePNG(background: CGColor(gray: 0, alpha: 1))
        #expect(FaviconLuminance.needsLightBacking(pngData: png))
    }

    @Test("A dense dark glyph on an opaque white plate brought its own background")
    func darkGlyphOnWhitePlate() {
        let png = makePNG(
            background: CGColor(gray: 1, alpha: 1),
            glyph: CGColor(gray: 0, alpha: 1),
            glyphInset: 4)
        #expect(!FaviconLuminance.needsLightBacking(pngData: png))
    }

    @Test("Dark colors count as dark; saturated brand blue does not")
    func coloredArtwork() {
        let navy = makePNG(
            glyph: CGColor(red: 0, green: 0x1f / 255.0, blue: 0x3f / 255.0, alpha: 1))
        #expect(FaviconLuminance.needsLightBacking(pngData: navy))

        let blue = makePNG(
            background: CGColor(
                red: 0x34 / 255.0, green: 0x78 / 255.0, blue: 0xf6 / 255.0, alpha: 1))
        #expect(!FaviconLuminance.needsLightBacking(pngData: blue))
    }

    @Test("A ghosted dark glyph is judged by its ink color, not its composite")
    func lowAlphaGlyph() {
        let png = makePNG(glyph: CGColor(gray: 0, alpha: 0.3))
        #expect(FaviconLuminance.needsLightBacking(pngData: png))
    }

    @Test("Empty and undecodable images keep the default chip")
    func degenerateInputs() {
        #expect(!FaviconLuminance.needsLightBacking(pngData: makePNG()))
        #expect(!FaviconLuminance.needsLightBacking(pngData: Data("not a png".utf8)))
    }
}

/// A square PNG: optional full-bleed background, optional inset glyph square.
private func makePNG(
    edge: Int = 64,
    background: CGColor? = nil,
    glyph: CGColor? = nil,
    glyphInset: CGFloat = 16
) -> Data {
    let context = CGContext(
        data: nil,
        width: edge,
        height: edge,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let bounds = CGRect(x: 0, y: 0, width: edge, height: edge)
    if let background {
        context.setFillColor(background)
        context.fill(bounds)
    }
    if let glyph {
        context.setFillColor(glyph)
        context.fill(bounds.insetBy(dx: glyphInset, dy: glyphInset))
    }
    let image = context.makeImage()!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}
