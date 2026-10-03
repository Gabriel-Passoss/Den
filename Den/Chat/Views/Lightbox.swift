import SwiftUI

struct Lightbox: View {
    @Binding var zoomed: ZoomedImage?

    var body: some View {
        if let zoomed, let image = ImageCache.decodedImage(zoomed.data) {
            ZStack {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .transition(.opacity)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 24)
                    .padding(36)
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
            }
            .contentShape(Rectangle())
            .onTapGesture { close() }
            .help("Clique ou Esc para fechar")
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { zoomed = nil }
    }
}
