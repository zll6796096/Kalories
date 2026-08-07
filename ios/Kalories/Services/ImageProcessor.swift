import UIKit

protocol ImageProcessing {
    @MainActor
    func dataURI(for image: UIImage) throws -> String
}

struct ImageProcessor: ImageProcessing {
    static let maximumBytes = 3 * 1024 * 1024
    static let maximumDimension: CGFloat = 2_048

    var encoder: (UIImage, CGFloat) -> Data? = {
        $0.jpegData(compressionQuality: $1)
    }

    @MainActor
    func dataURI(for image: UIImage) throws -> String {
        let sourcePixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        guard
            sourcePixelSize.width.isFinite,
            sourcePixelSize.height.isFinite,
            sourcePixelSize.width > 0,
            sourcePixelSize.height > 0
        else {
            throw AppFailure.invalidImage
        }

        var dimension = Self.maximumDimension
        while dimension >= 768 {
            let normalized = redraw(
                image,
                sourcePixelSize: sourcePixelSize,
                maximumDimension: dimension
            )
            for quality in [0.85, 0.75, 0.65, 0.55, 0.45, 0.35, 0.25] {
                guard let data = encoder(normalized, quality) else {
                    throw AppFailure.invalidImage
                }
                guard data.count <= Self.maximumBytes else {
                    continue
                }
                guard
                    data.starts(with: [0xFF, 0xD8, 0xFF]),
                    UIImage(data: data) != nil
                else {
                    throw AppFailure.invalidImage
                }
                return "data:image/jpeg;base64," + data.base64EncodedString()
            }
            dimension *= 0.75
        }

        throw AppFailure.imageTooLarge
    }

    @MainActor
    private func redraw(
        _ image: UIImage,
        sourcePixelSize: CGSize,
        maximumDimension: CGFloat
    ) -> UIImage {
        let scale = min(
            1,
            maximumDimension / max(sourcePixelSize.width, sourcePixelSize.height)
        )
        let targetSize = CGSize(
            width: max(1, floor(sourcePixelSize.width * scale)),
            height: max(1, floor(sourcePixelSize.height * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        format.preferredRange = .standard

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
