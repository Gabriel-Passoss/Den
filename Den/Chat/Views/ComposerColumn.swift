import SwiftUI

extension View {
    func aboveComposer(fade: CGFloat) -> some View {
        padding(.horizontal, 32)
            .frame(maxWidth: 784)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background {
                LinearGradient(colors: [Theme.canvas.opacity(0), Theme.canvas],
                               startPoint: .top, endPoint: .init(x: 0.5, y: fade))
            }
    }
}
