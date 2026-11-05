import SwiftUI
import AppKit

/// The single place Slate asks for Liquid Glass.
///
/// Rules, from `docs/UI_REDESIGN.md`: glass is chrome, never canvas. Toolbars,
/// floating controls and the welcome card get glass; the editor and the reading
/// pane stay opaque. Everything goes through here so the `macOS 26` APIs live
/// behind one `#available` check and the deployment target keeps working.
enum GlassSupport {
    /// Whether the current system settings demand an opaque surface. Reduce
    /// Transparency and Increase Contrast both do: a blurred surface on top of
    /// low-contrast text is exactly what those settings exist to prevent.
    @MainActor
    static var prefersOpaqueSurfaces: Bool {
        let workspace = NSWorkspace.shared
        return workspace.accessibilityDisplayShouldReduceTransparency
            || workspace.accessibilityDisplayShouldIncreaseContrast
    }

    /// A glass surface for `content`. Prefer this over reaching for a material
    /// directly so a future tweak happens in one file.
    @ViewBuilder
    static func surface<Content: View>(cornerRadius: CGFloat = 12,
                                       tint: Color? = nil,
                                       interactive: Bool = false,
                                       @ViewBuilder content: () -> Content) -> some View {
        content().slateGlass(cornerRadius: cornerRadius,
                             tint: tint,
                             interactive: interactive)
    }
}

extension View {
    /// Rounded glass that degrades in this order: native glass on macOS 26, a
    /// material before that, and an opaque surface under Reduce Transparency or
    /// Increase Contrast.
    func slateGlass(cornerRadius: CGFloat = 12,
                    tint: Color? = nil,
                    interactive: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius,
                              tint: tint,
                              interactive: interactive))
    }

    /// The primary action in a toolbar: a glass button on macOS 26, a bordered
    /// prominent button before that.
    @ViewBuilder
    func slateProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

/// Groups glass shapes that sit within ~20 pt of each other so they merge into
/// one body and animate as one, instead of two blobs fighting for pixels.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    /// Read through the environment so a settings change repaints without a
    /// relaunch; `GlassSupport.prefersOpaqueSurfaces` is the AppKit view of the
    /// same settings for non-view call sites.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var isOpaque: Bool {
        reduceTransparency
            || contrast == .increased
            // Developer escape hatch: `SLATE_OPAQUE_CHROME=1` renders the whole
            // app without glass, which is also how the fallback is smoke-tested.
            || ProcessInfo.processInfo.environment["SLATE_OPAQUE_CHROME"] == "1"
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isOpaque {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}
