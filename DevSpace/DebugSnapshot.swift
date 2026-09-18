#if DEBUG
import AppKit

enum DebugSnapshot {
    static func arm() {
        guard let path = ProcessInfo.processInfo.environment["DEVSPACE_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            capture(to: path)

            if ProcessInfo.processInfo.environment["DEVSPACE_SNAPSHOT_STAY"] == nil {
                NSApp.terminate(nil)
            }
        }
    }

    private static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),

              let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)
        else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))

        var info = "window frame: \(window.frame)\n"
        info += "styleMask.fullSizeContentView: \(window.styleMask.contains(.fullSizeContentView))\n"
        info += "titlebarAppearsTransparent: \(window.titlebarAppearsTransparent)\n"
        info += "titleVisibility: \(window.titleVisibility.rawValue)\n"
        info += "toolbar: \(window.toolbar.map { String(describing: type(of: $0)) } ?? "nenhuma")\n"
        info += hierarchy(of: frame, depth: 0, maxDepth: 12)
        try? info.write(toFile: path + ".txt", atomically: true, encoding: .utf8)
    }

    private static func hierarchy(of view: NSView, depth: Int, maxDepth: Int) -> String {
        guard depth <= maxDepth else { return "" }
        let pad = String(repeating: "  ", count: depth)
        var out = "\(pad)\(type(of: view)) \(view.frame)\n"
        for sub in view.subviews {
            out += hierarchy(of: sub, depth: depth + 1, maxDepth: maxDepth)
        }
        return out
    }
}
#endif
