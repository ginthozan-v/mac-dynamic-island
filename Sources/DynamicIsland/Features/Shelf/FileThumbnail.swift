import QuickLookThumbnailing
import SwiftUI

/// Real file previews (screenshots, images, PDFs…) via Quick Look, falling back to the Finder icon.
struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    var cornerRadius: CGFloat = 5
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            }
        }
        .frame(width: size, height: size)
        .task(id: url) { image = await Self.thumbnail(for: url, size: size) }
    }

    nonisolated static func thumbnail(for url: URL, size: CGFloat) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size), scale: 2, representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.cgImage)
            }
        }
    }
}
