import SwiftUI
import AppKit

/// Window-level chrome shared by every vault window.
enum WindowChrome {
    /// A modern Mac window: the sidebar and toolbar run edge to edge, the
    /// titlebar is transparent, and the title moves into the toolbar row.
    @MainActor
    static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
    }
}

/// Soft fade for content scrolling under the toolbar. Falls back to the plain
/// system behaviour before macOS 26.
struct ScrollEdgeFade: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

/// Window background material. Before macOS 15 the window keeps its standard
/// background; from 15 on the system owns the translucent window surface.
struct WindowMaterial: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(.thinMaterial, for: .window)
        } else {
            content
        }
    }
}
