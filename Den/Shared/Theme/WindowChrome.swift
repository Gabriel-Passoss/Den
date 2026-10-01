import AppKit
import SwiftUI

struct WindowChrome: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.fullScreenChanged = fullScreenChanged
        return view
    }

    func updateNSView(_ view: ChromeView, context: Context) {
        view.fullScreenChanged = fullScreenChanged
    }

    private var fullScreenChanged: (Bool) -> Void {
        let binding = $isFullScreen
        return { value in
            guard binding.wrappedValue != value else { return }
            binding.wrappedValue = value
        }
    }

    final class ChromeView: NSView {
        var fullScreenChanged: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var titleObservation: NSKeyValueObservation?
        private var placing = false

        static let lightsLeading: CGFloat = 20

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers = []
            guard let window else { return }

            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = NSColor(Theme.canvas)

            let relayout: [NSNotification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didChangeScreenNotification,
            ]
            for name in relayout {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.placeTrafficLights() }
                })
            }
            observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification,
                                                object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fullScreenChanged?(true) }
            })
            observers.append(center.addObserver(forName: NSWindow.willExitFullScreenNotification,
                                                object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fullScreenChanged?(false) }
            })
            if let close = window.standardWindowButton(.closeButton),
               let titlebar = close.superview, let container = titlebar.superview {
                for view in [container, titlebar, close] {
                    view.postsFrameChangedNotifications = true
                    observers.append(center.addObserver(forName: NSView.frameDidChangeNotification,
                                                        object: view, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.placeTrafficLights() }
                    })
                }
            }
            titleObservation = window.observe(\.title, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.placeTrafficLights() }
            }
            fullScreenChanged?(window.styleMask.contains(.fullScreen))
            placeTrafficLights()
            DispatchQueue.main.async { [weak self] in
                self?.placeTrafficLights()
                if window.firstResponder is NSTextView { window.makeFirstResponder(nil) }
            }
        }

        func placeTrafficLights() {
            guard !placing, let window, !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let minimize = window.standardWindowButton(.miniaturizeButton),
                  let zoom = window.standardWindowButton(.zoomButton),
                  let container = close.superview?.superview else { return }
            placing = true
            defer { placing = false }

            let height = Theme.headerHeight
            var frame = container.frame
            frame.size.height = height
            frame.origin.y = window.frame.height - height
            if container.frame != frame { container.frame = frame }

            let spacing = max(minimize.frame.minX - close.frame.minX, close.frame.width + 6)
            for (index, button) in [close, minimize, zoom].enumerated() {
                let origin = NSPoint(x: Self.lightsLeading + CGFloat(index) * spacing,
                                     y: ((height - button.frame.height) / 2).rounded())
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
            titleObservation?.invalidate()
        }
    }
}

struct ResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    var growsTowardTrailing = true

    @State private var origin: Double?

    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let base = origin ?? width
                                if origin == nil { origin = width }
                                let delta = growsTowardTrailing ? value.translation.width
                                                                : -value.translation.width
                                width = min(max(base + delta, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in origin = nil }
                    )
            }
            .zIndex(1)
            .accessibilityHidden(true)
    }
}

struct TopBar<Content: View>: View {
    var leadingInset: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10) { content() }
            .padding(.leading, leadingInset)
            .padding(.trailing, 14)
            .frame(height: Theme.headerHeight)
            .frame(maxWidth: .infinity)
            .windowDragArea()
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.border).frame(height: 1)
            }
    }
}

extension View {
    func windowDragArea() -> some View {
        background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .onTapGesture(count: 2) { NSApp.keyWindow?.performZoom(nil) }
        }
    }
}
