import UIKit
import XCTest
@testable import Kalories

final class ImageProcessorTests: XCTestCase {
    private let dataURIPrefix = "data:image/jpeg;base64,"

    @MainActor
    func testLargeImageProducesBoundedJPEGDataURI() throws {
        let source = makeImage(size: CGSize(width: 4_000, height: 3_000)) { bounds in
            UIColor.systemOrange.setFill()
            UIRectFill(bounds)
            UIColor.systemBlue.setFill()
            UIRectFill(CGRect(x: bounds.midX, y: 0, width: bounds.width / 2, height: bounds.height))
        }

        let dataURI = try ImageProcessor().dataURI(for: source)

        XCTAssertTrue(dataURI.hasPrefix(dataURIPrefix))
        let (jpegData, decoded) = try decode(dataURI)
        XCTAssertEqual(Array(jpegData.prefix(3)), [0xFF, 0xD8, 0xFF])
        XCTAssertLessThanOrEqual(jpegData.count, ImageProcessor.maximumBytes)
        let pixels = try pixelSize(of: decoded)
        XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), Int(ImageProcessor.maximumDimension))
        XCTAssertEqual(Double(pixels.width) / Double(pixels.height), 4.0 / 3.0, accuracy: 0.01)
    }

    @MainActor
    func testSmallImageIsNotUpscaledInDecodedPixels() throws {
        let source = makeImage(size: CGSize(width: 320, height: 180)) { bounds in
            UIColor.systemGreen.setFill()
            UIRectFill(bounds)
        }

        let dataURI = try ImageProcessor().dataURI(for: source)

        let (_, decoded) = try decode(dataURI)
        XCTAssertEqual(try pixelSize(of: decoded), PixelSize(width: 320, height: 180))
    }

    @MainActor
    func testNonUpOrientationIsRenderedIntoUprightPixels() throws {
        let raw = makeImage(size: CGSize(width: 120, height: 80)) { bounds in
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height))
            UIColor.blue.setFill()
            UIRectFill(CGRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height))
        }
        let cgImage = try XCTUnwrap(raw.cgImage)
        let rotated = UIImage(cgImage: cgImage, scale: 1, orientation: .right)

        let dataURI = try ImageProcessor().dataURI(for: rotated)

        let (_, decoded) = try decode(dataURI)
        XCTAssertEqual(decoded.imageOrientation, .up)
        XCTAssertEqual(try pixelSize(of: decoded), PixelSize(width: 80, height: 120))

        let firstHalf = try rgbaPixel(in: decoded, x: 40, y: 20)
        let secondHalf = try rgbaPixel(in: decoded, x: 40, y: 100)
        XCTAssertTrue(
            (firstHalf.isPredominantlyRed && secondHalf.isPredominantlyBlue)
                || (firstHalf.isPredominantlyBlue && secondHalf.isPredominantlyRed),
            "Expected orientation redraw to rotate the red/blue split into opposite vertical halves"
        )
    }

    @MainActor
    func testOversizedEncodingExhaustsBoundedFallbacks() {
        let image = makeImage(size: CGSize(width: 4_000, height: 3_000)) { bounds in
            UIColor.white.setFill()
            UIRectFill(bounds)
        }
        let oversized = Data(repeating: 0, count: ImageProcessor.maximumBytes + 1)
        var attempts: [(PixelSize, CGFloat)] = []
        let processor = ImageProcessor { normalized, quality in
            let size = normalized.cgImage.map { PixelSize(width: $0.width, height: $0.height) }
                ?? PixelSize(width: 0, height: 0)
            attempts.append((size, quality))
            return oversized
        }

        XCTAssertThrowsError(try processor.dataURI(for: image)) { error in
            XCTAssertEqual(error as? AppFailure, .imageTooLarge)
        }
        XCTAssertEqual(attempts.count, 28)
        XCTAssertEqual(attempts.first?.0, PixelSize(width: 2_048, height: 1_536))
        XCTAssertEqual(attempts.last?.0, PixelSize(width: 864, height: 648))
        XCTAssertEqual(attempts.map(\.1), Array(repeating: [0.85, 0.75, 0.65, 0.55, 0.45, 0.35, 0.25], count: 4).flatMap { $0 })
    }

    @MainActor
    func testEncoderFailureMapsToInvalidImage() {
        let image = makeImage(size: CGSize(width: 100, height: 100)) { bounds in
            UIColor.white.setFill()
            UIRectFill(bounds)
        }
        var encodingAttempts = 0
        let processor = ImageProcessor { _, _ in
            encodingAttempts += 1
            return nil
        }

        XCTAssertThrowsError(try processor.dataURI(for: image)) { error in
            XCTAssertEqual(error as? AppFailure, .invalidImage)
        }
        XCTAssertEqual(encodingAttempts, 1)
    }

    @MainActor
    func testEmptyImageIsRejectedBeforeEncoding() {
        var encodingAttempts = 0
        let processor = ImageProcessor { _, _ in
            encodingAttempts += 1
            return Data()
        }

        XCTAssertThrowsError(try processor.dataURI(for: UIImage())) { error in
            XCTAssertEqual(error as? AppFailure, .invalidImage)
        }
        XCTAssertEqual(encodingAttempts, 0)
    }

    @MainActor
    private func makeImage(
        size: CGSize,
        drawing: (CGRect) -> Void
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            drawing(CGRect(origin: .zero, size: size))
        }
    }

    @MainActor
    private func decode(_ dataURI: String) throws -> (Data, UIImage) {
        XCTAssertTrue(dataURI.hasPrefix(dataURIPrefix))
        let payload = String(dataURI.dropFirst(dataURIPrefix.count))
        let data = try XCTUnwrap(Data(base64Encoded: payload))
        return (data, try XCTUnwrap(UIImage(data: data)))
    }

    private func pixelSize(of image: UIImage) throws -> PixelSize {
        let cgImage = try XCTUnwrap(image.cgImage)
        return PixelSize(width: cgImage.width, height: cgImage.height)
    }

    private func rgbaPixel(in image: UIImage, x: Int, y: Int) throws -> RGBA {
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertTrue((0..<cgImage.width).contains(x))
        XCTAssertTrue((0..<cgImage.height).contains(y))
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.interpolationQuality = .none
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        )
        let offset = ((y * cgImage.width) + x) * 4
        return RGBA(red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2])
    }
}

private struct PixelSize: Equatable {
    let width: Int
    let height: Int
}

private struct RGBA {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var isPredominantlyRed: Bool {
        red > 180 && green < 80 && blue < 80
    }

    var isPredominantlyBlue: Bool {
        blue > 180 && red < 80 && green < 80
    }
}
