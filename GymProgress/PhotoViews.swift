import SwiftUI

struct StoredPhoto: View {
    let fileName: String
    var maxPixel = 500
    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.15)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: fileName) {
                let name = fileName, size = maxPixel
                image = await Task.detached { PhotoStore.thumbnail(named: name, maxPixel: size) }.value
            }
    }
}

struct AlignedPhoto: View {
    let photo: ProgressPhoto

    var body: some View {
        GeometryReader { geo in
            StoredPhoto(fileName: photo.fileName, maxPixel: 1600)
                .scaleEffect(photo.alignScale)
                .offset(x: photo.alignOffsetX * geo.size.width, y: photo.alignOffsetY * geo.size.height)
        }
        .clipped()
    }
}

struct Badge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: .capsule)
            .padding(6)
    }
}
