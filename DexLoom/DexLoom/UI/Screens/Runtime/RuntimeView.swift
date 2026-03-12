import SwiftUI
import WebKit

struct RuntimeView: View {
    @ObservedObject var bridge: RuntimeBridge

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if bridge.isExecuting {
                    // Interpreter is actively running on background thread
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Executing DEX bytecode...")
                            .font(.dxBody)
                            .foregroundStyle(Color.dxText)
                        Button {
                            bridge.cancelExecution()
                        } label: {
                            Label("Cancel Execution", systemImage: "xmark.circle.fill")
                                .foregroundStyle(Color.red)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dxBackground)
                } else if bridge.isRunning, let root = bridge.renderTree {
                    // Render the Android UI tree
                    ScrollView {
                        AndroidViewRenderer(node: root, bridge: bridge)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Color.white)
                } else if bridge.isRunning {
                    // Running but no render tree yet
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.green)
                        Text("Activity executed successfully")
                            .font(.dxBody)
                            .foregroundStyle(Color.dxText)
                        Text("No visual UI was produced.\nThe app may use Compose or have no setContentView call.")
                            .font(.dxCaption)
                            .foregroundStyle(Color.dxTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dxBackground)
                } else if bridge.isLoaded {
                    VStack(spacing: 16) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.dxTextSecondary)
                        Text("APK loaded. Tap Run to start.")
                            .font(.dxBody)
                            .foregroundStyle(Color.dxTextSecondary)
                        Button("Run Activity") {
                            bridge.run()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.dxPrimary)

                        if let error = bridge.errorMessage {
                            VStack(spacing: 8) {
                                Text(error)
                                    .font(.dxCaption)
                                    .foregroundStyle(Color.dxError)
                                    .multilineTextAlignment(.center)
                                Button("Copy Error + Logs") {
                                    let logText = bridge.copyLogsToClipboard()
                                    let full = "Error: \(error)\n\n--- Logs ---\n\(logText)"
                                    UIPasteboard.general.string = full
                                }
                                .font(.dxCaption)
                                .foregroundStyle(Color.dxPrimary)
                            }
                            .padding()
                            .background(Color.dxError.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dxBackground)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "cpu")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.dxTextSecondary)
                        Text("No APK loaded")
                            .font(.dxBody)
                            .foregroundStyle(Color.dxTextSecondary)
                        Text("Import an APK from the Home tab")
                            .font(.dxCaption)
                            .foregroundStyle(Color.dxTextSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dxBackground)
                }
            }
            .navigationTitle("Runtime")
        }
    }
}

// MARK: - Color helpers

private func argbColor(_ argb: UInt32) -> Color {
    let a = Double((argb >> 24) & 0xFF) / 255.0
    let r = Double((argb >> 16) & 0xFF) / 255.0
    let g = Double((argb >> 8) & 0xFF) / 255.0
    let b = Double(argb & 0xFF) / 255.0
    return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
}

// MARK: - Android View Renderer

/// Threshold above which child rendering switches to LazyVStack/LazyHStack
private let lazyChildThreshold = 20

/// Threshold above which RecyclerView items use visible-only rendering
private let recyclerViewLazyThreshold = 50

struct AndroidViewRenderer: View {
    let node: RenderNode
    let bridge: RuntimeBridge

    var body: some View {
        // Handle Android view visibility: VISIBLE=0, INVISIBLE=4, GONE=8
        if node.visibility == DX_GONE {
            // GONE: takes no space at all
            EmptyView()
        } else {
            viewContent
                .opacity(node.visibility == DX_INVISIBLE ? 0 : 1)
        }
    }

    @ViewBuilder
    private var viewContent: some View {
        if !node.drawCommands.isEmpty {
            // View with Canvas draw commands — render using SwiftUI Canvas
            CanvasDrawView(commands: node.drawCommands, node: node)
                .applyAndroidStyle(node: node)
                .applyGestures(node: node, bridge: bridge)
        } else if (node.type == DX_VIEW_TEXT_VIEW || node.type == DX_VIEW_BUTTON ||
           node.type == DX_VIEW_EDIT_TEXT || node.type == DX_VIEW_IMAGE_VIEW ||
           node.type == DX_VIEW_SWITCH || node.type == DX_VIEW_CHECKBOX ||
           node.type == DX_VIEW_RADIO_BUTTON || node.type == DX_VIEW_PROGRESS_BAR ||
           node.type == DX_VIEW_SEEK_BAR || node.type == DX_VIEW_RATING_BAR ||
           node.type == DX_VIEW_SPINNER || node.type == DX_VIEW_CHIP ||
           node.type == DX_VIEW_WEB_VIEW || node.type == DX_VIEW_VIEW)
           && node.children.isEmpty {
            leafView
                .applyAndroidStyle(node: node)
                .applyGestures(node: node, bridge: bridge)
        } else {
            // Container views
            containerView
                .applyAndroidStyle(node: node)
                .applyGestures(node: node, bridge: bridge)
        }
    }

    // MARK: - Leaf views

    @ViewBuilder
    private var leafView: some View {
        switch node.type {
        case DX_VIEW_TEXT_VIEW:
            textView

        case DX_VIEW_BUTTON:
            buttonView

        case DX_VIEW_EDIT_TEXT:
            editTextView

        case DX_VIEW_IMAGE_VIEW:
            imageView

        case DX_VIEW_SWITCH:
            switchView

        case DX_VIEW_CHECKBOX:
            checkboxView

        case DX_VIEW_RADIO_BUTTON:
            radioButtonView

        case DX_VIEW_PROGRESS_BAR:
            ProgressView()
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

        case DX_VIEW_SEEK_BAR:
            seekBarView

        case DX_VIEW_RATING_BAR:
            ratingBarView

        case DX_VIEW_SPINNER:
            spinnerView

        case DX_VIEW_CHIP:
            chipView

        case DX_VIEW_WEB_VIEW:
            webViewRendered

        case DX_VIEW_VIEW:
            // Generic <View/> — spacer or divider
            Rectangle()
                .fill(node.bgColor != 0 ? argbColor(node.bgColor) : Color.clear)
                .frame(height: 1)

        default:
            EmptyView()
        }
    }

    // MARK: - Container views

    @ViewBuilder
    private var containerView: some View {
        switch node.type {
        case DX_VIEW_LINEAR_LAYOUT:
            if node.orientation == DX_ORIENTATION_VERTICAL {
                lazyVerticalChildViews
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                lazyHorizontalChildViews
            }

        case DX_VIEW_CONSTRAINT_LAYOUT:
            ConstraintLayoutView(node: node, bridge: bridge)

        case DX_VIEW_FRAME_LAYOUT:
            ZStack(alignment: .topLeading) {
                childViews
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case DX_VIEW_RELATIVE_LAYOUT:
            // RelativeLayout: use ZStack with per-child alignment based on relative_flags
            ZStack {
                ForEach(node.children) { child in
                    AndroidViewRenderer(node: child, bridge: bridge)
                        .frame(
                            maxWidth: relativeNeedsFullWidth(child) ? .infinity : nil,
                            maxHeight: relativeNeedsFullHeight(child) ? .infinity : nil,
                            alignment: relativeChildAlignment(child)
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

        case DX_VIEW_SCROLL_VIEW:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    childViews
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case DX_VIEW_SWIPE_REFRESH:
            SwipeRefreshContainerView(node: node, bridge: bridge)

        case DX_VIEW_CARD_VIEW:
            VStack(alignment: .leading, spacing: 0) {
                childViews
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

        case DX_VIEW_TOOLBAR:
            HStack(spacing: 8) {
                if let text = node.text {
                    Text(text)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))

        case DX_VIEW_LIST_VIEW, DX_VIEW_GRID_VIEW:
            // ListView / GridView — vertical list of adapter-provided children
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(node.children) { child in
                        AndroidViewRenderer(node: child, bridge: bridge)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case DX_VIEW_TAB_LAYOUT:
            // TabLayout — render tabs as horizontal buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    childViews
                }
            }
            .frame(maxWidth: .infinity)

        case DX_VIEW_VIEW_PAGER:
            // ViewPager — show first page only (no swipe)
            ZStack(alignment: .topLeading) {
                if let firstChild = node.children.first {
                    AndroidViewRenderer(node: firstChild, bridge: bridge)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case DX_VIEW_RADIO_GROUP:
            // RadioGroup — vertical list of radio buttons
            VStack(alignment: .leading, spacing: 4) {
                childViews
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case DX_VIEW_BOTTOM_NAV:
            // BottomNavigationView — horizontal bar at bottom
            HStack {
                childViews
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .overlay(alignment: .top) {
                Divider()
            }

        case DX_VIEW_FAB:
            // FloatingActionButton — circular button
            Button {
                bridge.dispatchClick(viewId: node.viewId)
            } label: {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(node.bgColor != 0 ? argbColor(node.bgColor) : Color.blue)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            }

        case DX_VIEW_RECYCLER_VIEW:
            // RecyclerView — use LazyVStack for view recycling
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(node.children) { child in
                        AndroidViewRenderer(node: child, bridge: bridge)
                            .id(child.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            // DX_VIEW_VIEW_GROUP, etc.
            lazyVerticalChildViews
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Child rendering

    @ViewBuilder
    private var childViews: some View {
        ForEach(node.children) { child in
            if child.type.rawValue >= 0 {  // always true, just keeps ForEach happy
                AndroidViewRenderer(node: child, bridge: bridge)
            }
        }
    }

    /// Lazy vertical child rendering for containers with many children.
    /// Uses LazyVStack when child count exceeds lazyChildThreshold.
    @ViewBuilder
    private var lazyVerticalChildViews: some View {
        if node.children.count > lazyChildThreshold {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(node.children) { child in
                    AndroidViewRenderer(node: child, bridge: bridge)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                childViews
            }
        }
    }

    /// Lazy horizontal child rendering for containers with many children.
    /// Uses LazyHStack when child count exceeds lazyChildThreshold.
    @ViewBuilder
    private var lazyHorizontalChildViews: some View {
        if node.children.count > lazyChildThreshold {
            LazyHStack(alignment: .center, spacing: 0) {
                ForEach(node.children) { child in
                    AndroidViewRenderer(node: child, bridge: bridge)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 0) {
                childViews
            }
        }
    }

    // MARK: - Specific view builders

    private var textView: some View {
        Text(node.text ?? "")
            .font(.system(size: max(sp(node.textSize), 1)))
            .foregroundStyle(node.textColor != 0 ? argbColor(node.textColor) : .black)
            .multilineTextAlignment(gravityAlignment)
            .frame(maxWidth: .infinity, alignment: gravityFrameAlignment)
    }

    private var buttonView: some View {
        Button {
            bridge.dispatchClick(viewId: node.viewId)
        } label: {
            Text(node.text ?? "Button")
                .font(.system(size: max(sp(node.textSize), 1)))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var editTextView: some View {
        EditTextFieldView(
            initialText: node.text ?? "",
            hint: node.hint ?? "",
            textSize: sp(node.textSize),
            inputType: node.inputType,
            viewId: node.viewId,
            bridge: bridge
        )
    }

    private var imageView: some View {
        Group {
            if let pathData = node.vectorPathData, !pathData.isEmpty {
                VectorDrawableView(
                    pathData: pathData,
                    fillColor: node.vectorFillColor,
                    strokeColor: node.vectorStrokeColor,
                    strokeWidth: node.vectorStrokeWidth,
                    viewportWidth: node.vectorWidth,
                    viewportHeight: node.vectorHeight
                )
                .frame(maxWidth: .infinity, minHeight: 40)
            } else if let data = node.imageData, let uiImage = UIImage(data: data) {
                if node.isNinePatch {
                    // 9-patch PNG: use stretch regions as cap insets for resizable rendering
                    let capInsets = UIEdgeInsets(
                        top: CGFloat(node.ninePatchStretchY.0),
                        left: CGFloat(node.ninePatchStretchX.0),
                        bottom: max(CGFloat(uiImage.size.height) - CGFloat(node.ninePatchStretchY.1), 0),
                        right: max(CGFloat(uiImage.size.width) - CGFloat(node.ninePatchStretchX.1), 0)
                    )
                    let resizable = uiImage.resizableImage(withCapInsets: capInsets, resizingMode: .stretch)
                    Image(uiImage: resizable)
                        .resizable()
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .padding(EdgeInsets(
                            top: CGFloat(node.ninePatchPadding.1),
                            leading: CGFloat(node.ninePatchPadding.0),
                            bottom: CGFloat(node.ninePatchPadding.3),
                            trailing: CGFloat(node.ninePatchPadding.2)
                        ))
                } else {
                    // Apply scaleType: 0=fitCenter, 1=center, 2=centerCrop, 3=centerInside, 4=fitXY, 5=fitStart, 6=fitEnd
                    switch node.scaleType {
                    case 2: // centerCrop
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .clipped()
                    case 4: // fitXY - stretch without preserving aspect ratio
                        Image(uiImage: uiImage)
                            .resizable()
                            .frame(maxWidth: .infinity, minHeight: 40)
                    case 1: // center - no resizing, natural size
                        Image(uiImage: uiImage)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    case 5: // fitStart - fit with top-leading alignment
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                    case 6: // fitEnd - fit with bottom-trailing alignment
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .bottomTrailing)
                    default: // 0=fitCenter, 3=centerInside - fit preserving aspect ratio
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private var switchView: some View {
        HStack {
            if let text = node.text {
                Text(text)
                    .font(.system(size: max(sp(node.textSize), 1)))
            }
            Spacer()
            Image(systemName: node.isChecked ? "switch.2" : "switch.2")
                .foregroundStyle(node.isChecked ? .blue : .gray)
        }
    }

    private var checkboxView: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isChecked ? "checkmark.square.fill" : "square")
                .foregroundStyle(node.isChecked ? .blue : .gray)
            if let text = node.text {
                Text(text)
                    .font(.system(size: max(sp(node.textSize), 1)))
            }
        }
    }

    private var radioButtonView: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isChecked ? "circle.inset.filled" : "circle")
                .foregroundStyle(node.isChecked ? .blue : .gray)
            if let text = node.text {
                Text(text)
                    .font(.system(size: max(sp(node.textSize), 1)))
            }
        }
    }

    private var seekBarView: some View {
        HStack {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 80, height: 4)
            Circle()
                .fill(Color.blue)
                .frame(width: 20, height: 20)
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 4)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }

    private var ratingBarView: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < 3 ? "star.fill" : "star")
                    .foregroundStyle(i < 3 ? .yellow : .gray.opacity(0.4))
            }
        }
    }

    private var spinnerView: some View {
        HStack {
            Text(node.text ?? "Select...")
                .foregroundStyle(node.text != nil ? .primary : .secondary)
            Spacer()
            Image(systemName: "chevron.down")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
        )
    }

    private var chipView: some View {
        Text(node.text ?? "Chip")
            .font(.system(size: max(sp(node.textSize), 12)))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(node.bgColor != 0 ? argbColor(node.bgColor) : Color.gray.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }

    private var webViewRendered: some View {
        WebViewWrapper(url: node.webURL, html: node.webHTML)
            .frame(maxWidth: .infinity, minHeight: 200)
            .frame(height: node.height > 0 ? dp(node.height) : 300)
    }

    // MARK: - Gravity helpers

    private var gravityAlignment: TextAlignment {
        let h = node.gravity & 0x07  // horizontal gravity bits
        if h == 1 { return .center }       // CENTER_HORIZONTAL
        if h == 5 { return .trailing }     // RIGHT / END
        return .leading
    }

    private var gravityFrameAlignment: Alignment {
        let h = node.gravity & 0x07
        if h == 1 { return .center }
        if h == 5 { return .trailing }
        return .leading
    }

    // MARK: - RelativeLayout helpers

    /// Compute SwiftUI alignment for a child inside a RelativeLayout ZStack
    private func relativeChildAlignment(_ child: RenderNode) -> Alignment {
        let f = child.relativeFlags

        // centerInParent takes priority
        if f & UInt16(DX_REL_CENTER_IN_PARENT) != 0 {
            return .center
        }

        // Determine horizontal alignment
        let left   = f & UInt16(DX_REL_ALIGN_PARENT_LEFT) != 0
        let right  = f & UInt16(DX_REL_ALIGN_PARENT_RIGHT) != 0
        let centerH = f & UInt16(DX_REL_CENTER_HORIZONTAL) != 0

        // Determine vertical alignment
        let top    = f & UInt16(DX_REL_ALIGN_PARENT_TOP) != 0
        let bottom = f & UInt16(DX_REL_ALIGN_PARENT_BOTTOM) != 0
        let centerV = f & UInt16(DX_REL_CENTER_VERTICAL) != 0

        let h: HorizontalAlignment
        if centerH || (left && right) {
            h = .center
        } else if right {
            h = .trailing
        } else {
            h = .leading   // default or explicit left
        }

        let v: VerticalAlignment
        if centerV || (top && bottom) {
            v = .center
        } else if bottom {
            v = .bottom
        } else {
            v = .top       // default or explicit top
        }

        return Alignment(horizontal: h, vertical: v)
    }

    /// Whether this child should stretch horizontally (centerHorizontal or both left+right)
    private func relativeNeedsFullWidth(_ child: RenderNode) -> Bool {
        let f = child.relativeFlags
        let left  = f & UInt16(DX_REL_ALIGN_PARENT_LEFT) != 0
        let right = f & UInt16(DX_REL_ALIGN_PARENT_RIGHT) != 0
        return (left && right) || child.width == -1 // match_parent
    }

    /// Whether this child should stretch vertically (centerVertical or both top+bottom)
    private func relativeNeedsFullHeight(_ child: RenderNode) -> Bool {
        let f = child.relativeFlags
        let top    = f & UInt16(DX_REL_ALIGN_PARENT_TOP) != 0
        let bottom = f & UInt16(DX_REL_ALIGN_PARENT_BOTTOM) != 0
        return (top && bottom) || child.height == -1 // match_parent
    }
}

// MARK: - dp/sp/px to iOS points conversion
//
// Android dp (density-independent pixels) and iOS points are both defined
// relative to a 160dpi baseline. On iOS, 1pt = 1/163" (effectively 160dpi),
// so 1dp = 1pt regardless of screen scale (@2x, @3x).
//
// The C layer (dx_ui_decode_dimension) already converts all dimension units
// (px, dp, sp, pt, in, mm) to iOS-point-equivalent values before they reach
// Swift, so these functions apply no additional scaling. They exist as named
// conversion points so the mapping is explicit and can be adjusted if needed
// (e.g., for user-configurable text scaling).

/// Scale factor applied to all dp values. 1.0 is correct for standard iOS displays.
private let dpScale: CGFloat = 1.0

/// Scale factor for sp (text) values. Increase for accessibility large-text support.
private let spScale: CGFloat = 1.0

/// Convert Android dp to iOS points.
private func dp(_ value: Int32) -> CGFloat {
    CGFloat(value) * dpScale
}

/// Convert Android sp (text size) to iOS points.
private func sp(_ value: Float) -> CGFloat {
    CGFloat(value) * spScale
}

// MARK: - Android style modifier

private struct AndroidStyleModifier: ViewModifier {
    let node: RenderNode

    func body(content: Content) -> some View {
        content
            .applyLayoutSize(width: node.width, height: node.height, weight: node.weight,
                             measuredWidth: node.measuredWidth, measuredHeight: node.measuredHeight)
            .padding(.leading, dp(node.padding.0))
            .padding(.top, dp(node.padding.1))
            .padding(.trailing, dp(node.padding.2))
            .padding(.bottom, dp(node.padding.3))
            .background(shapeOrColorBackground)
            .applyFocusBorder(node: node)
            .opacity(Double(node.alpha))
            .rotationEffect(.degrees(Double(node.rotation)))
            .scaleEffect(x: CGFloat(node.scaleX), y: CGFloat(node.scaleY))
            .offset(x: CGFloat(node.translationX), y: CGFloat(node.translationY))
            .padding(.leading, dp(node.margin.0))
            .padding(.top, dp(node.margin.1))
            .padding(.trailing, dp(node.margin.2))
            .padding(.bottom, dp(node.margin.3))
    }

    @ViewBuilder
    private var shapeOrColorBackground: some View {
        if let shape = node.shapeBg {
            ShapeBackgroundView(shape: shape)
        } else if node.bgColor != 0 {
            argbColor(node.bgColor)
        } else {
            Color.clear
        }
    }
}

/// Renders a DxShapeDrawable as a SwiftUI shape background
private struct ShapeBackgroundView: View {
    let shape: ShapeBackground

    var body: some View {
        Group {
            if hasGradient {
                gradientShape
            } else {
                solidShape
            }
        }
    }

    private var hasGradient: Bool {
        shape.gradientStart != 0 || shape.gradientEnd != 0
    }

    @ViewBuilder
    private var solidShape: some View {
        switch shape.shapeType {
        case 1:  // oval
            Ellipse()
                .fill(fillColor)
                .overlay(strokeOverlayOval)
        default:  // rectangle (0) and others
            RoundedRectangle(cornerRadius: CGFloat(shape.cornerRadius))
                .fill(fillColor)
                .overlay(strokeOverlayRect)
        }
    }

    @ViewBuilder
    private var gradientShape: some View {
        let gradient = LinearGradient(
            colors: [argbColor(shape.gradientStart), argbColor(shape.gradientEnd)],
            startPoint: .top,
            endPoint: .bottom
        )
        switch shape.shapeType {
        case 1:  // oval
            Ellipse()
                .fill(gradient)
                .overlay(strokeOverlayOval)
        default:  // rectangle
            RoundedRectangle(cornerRadius: CGFloat(shape.cornerRadius))
                .fill(gradient)
                .overlay(strokeOverlayRect)
        }
    }

    @ViewBuilder
    private var strokeOverlayRect: some View {
        if shape.strokeWidth > 0 && shape.strokeColor != 0 {
            RoundedRectangle(cornerRadius: CGFloat(shape.cornerRadius))
                .stroke(argbColor(shape.strokeColor), lineWidth: CGFloat(shape.strokeWidth))
        }
    }

    @ViewBuilder
    private var strokeOverlayOval: some View {
        if shape.strokeWidth > 0 && shape.strokeColor != 0 {
            Ellipse()
                .stroke(argbColor(shape.strokeColor), lineWidth: CGFloat(shape.strokeWidth))
        }
    }

    private var fillColor: Color {
        shape.solidColor != 0 ? argbColor(shape.solidColor) : Color.clear
    }
}

private struct LayoutSizeModifier: ViewModifier {
    let width: Int32
    let height: Int32
    let weight: Float
    let measuredWidth: Float
    let measuredHeight: Float

    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: widthMin, idealWidth: nil, maxWidth: widthMax,
                minHeight: heightMin, idealHeight: nil, maxHeight: heightMax
            )
    }

    // width: -1 match_parent -> maxWidth: .infinity
    //        -2 wrap_content -> use measured size if available, else natural size (nil)
    //        >0 specific dp  -> fixed width (converted via dp())
    private var widthMin: CGFloat? {
        if width > 0 { return dp(width) }
        if width == -2 && measuredWidth > 0 { return CGFloat(measuredWidth) }
        return nil
    }
    private var widthMax: CGFloat? {
        if width == -1 || weight > 0 { return .infinity }   // match_parent or weighted
        if width > 0 { return dp(width) }
        if width == -2 && measuredWidth > 0 { return CGFloat(measuredWidth) }
        return nil  // wrap_content
    }
    private var heightMin: CGFloat? {
        if height > 0 { return dp(height) }
        if height == -2 && measuredHeight > 0 { return CGFloat(measuredHeight) }
        return nil
    }
    private var heightMax: CGFloat? {
        if height == -1 { return .infinity }
        if height > 0 { return dp(height) }
        if height == -2 && measuredHeight > 0 { return CGFloat(measuredHeight) }
        return nil  // wrap_content
    }
}

extension View {
    fileprivate func applyLayoutSize(width: Int32, height: Int32, weight: Float,
                                     measuredWidth: Float, measuredHeight: Float) -> some View {
        modifier(LayoutSizeModifier(width: width, height: height, weight: weight,
                                    measuredWidth: measuredWidth, measuredHeight: measuredHeight))
    }
}

extension View {
    fileprivate func applyAndroidStyle(node: RenderNode) -> some View {
        modifier(AndroidStyleModifier(node: node))
    }
}

extension View {
    /// Applies a blue border to focused EditText views
    @ViewBuilder
    fileprivate func applyFocusBorder(node: RenderNode) -> some View {
        if node.focused && node.type == DX_VIEW_EDIT_TEXT {
            self.overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.blue, lineWidth: 2)
            )
        } else {
            self
        }
    }
}

/// Applies tap and long-press gestures to views that have registered listeners.
/// Button and FAB views already handle clicks via SwiftUI Button, so they are excluded
/// from the tap gesture to avoid double-firing.
private struct GestureModifier: ViewModifier {
    let node: RenderNode
    let bridge: RuntimeBridge

    /// View types that already handle clicks via their own SwiftUI Button wrapper
    private var isButtonType: Bool {
        node.type == DX_VIEW_BUTTON || node.type == DX_VIEW_FAB
    }

    func body(content: Content) -> some View {
        content
            .applyTapGesture(
                hasListener: node.hasClickListener && !isButtonType,
                viewId: node.viewId,
                bridge: bridge
            )
            .applyLongPressGesture(
                hasListener: node.hasLongClickListener,
                viewId: node.viewId,
                bridge: bridge
            )
    }
}

extension View {
    fileprivate func applyGestures(node: RenderNode, bridge: RuntimeBridge) -> some View {
        modifier(GestureModifier(node: node, bridge: bridge))
    }

    @ViewBuilder
    fileprivate func applyTapGesture(hasListener: Bool, viewId: UInt32, bridge: RuntimeBridge) -> some View {
        if hasListener {
            self.contentShape(Rectangle())
                .onTapGesture {
                    bridge.dispatchClick(viewId: viewId)
                }
        } else {
            self
        }
    }

    @ViewBuilder
    fileprivate func applyLongPressGesture(hasListener: Bool, viewId: UInt32, bridge: RuntimeBridge) -> some View {
        if hasListener {
            self.onLongPressGesture {
                bridge.dispatchLongClick(viewId: viewId)
            }
        } else {
            self
        }
    }
}

/// SwipeRefreshLayout rendered as a ScrollView with pull-to-refresh support
private struct SwipeRefreshContainerView: View {
    let node: RenderNode
    let bridge: RuntimeBridge
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(node.children) { child in
                    AndroidViewRenderer(node: child, bridge: bridge)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable {
            isRefreshing = true
            bridge.dispatchRefresh(viewId: node.viewId)
            // Brief delay so the spinner is visible
            try? await Task.sleep(nanoseconds: 500_000_000)
            isRefreshing = false
        }
    }
}

// MARK: - ConstraintLayout solver

/// A simplified ConstraintLayout renderer.
/// For each child, determines horizontal and vertical positioning based on constraint anchors.
/// Supports: anchoring to parent edges, centering (with bias), and anchoring to sibling edges.
/// Uses GeometryReader + explicit offsets to place children within a ZStack.
private let kConstraintParent: UInt32 = 0xFFFFFFFF

private struct ConstraintLayoutView: View {
    let node: RenderNode
    let bridge: RuntimeBridge

    var body: some View {
        GeometryReader { geo in
            let parentW = geo.size.width
            let parentH = geo.size.height
            let hChains = detectHorizontalChains()
            let vChains = detectVerticalChains()
            let chainMemberIds = collectChainMemberIds(hChains: hChains, vChains: vChains)

            ZStack(alignment: .topLeading) {
                // Render horizontal chains
                ForEach(Array(hChains.enumerated()), id: \.offset) { _, chain in
                    renderHorizontalChain(chain, parentSize: geo.size)
                }
                // Render vertical chains
                ForEach(Array(vChains.enumerated()), id: \.offset) { _, chain in
                    renderVerticalChain(chain, parentSize: geo.size)
                }
                // Render non-chain, non-guideline children individually
                ForEach(node.children) { child in
                    if !child.isGuideline && !chainMemberIds.contains(child.viewId) {
                        let solved = solveChild(child, parentSize: geo.size)
                        AndroidViewRenderer(node: child, bridge: bridge)
                            .frame(
                                width: solved.width,
                                height: solved.height
                            )
                            .frame(
                                maxWidth: solved.maxWidth,
                                maxHeight: solved.maxHeight
                            )
                            .alignmentGuide(.leading) { _ in -solved.x }
                            .alignmentGuide(.top) { _ in -solved.y }
                    }
                }
            }
            .frame(width: parentW, height: parentH, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: constraintLayoutMinHeight)
    }

    /// Estimate a reasonable minimum height for the ConstraintLayout based on children
    private var constraintLayoutMinHeight: CGFloat {
        // If any child has an explicit height, use the max; otherwise use a sensible default
        var maxH: CGFloat = 0
        for child in node.children {
            if child.height > 0 {
                maxH = max(maxH, dp(child.height) + dp(child.margin.1) + dp(child.margin.3))
            } else {
                maxH = max(maxH, 48) // minimum per child
            }
        }
        // For ConstraintLayout with match_parent height, don't restrict
        if node.height == -1 { return maxH }
        if node.height > 0 { return dp(node.height) }
        // wrap_content: sum visible children heights as rough estimate
        var total: CGFloat = 0
        for child in node.children {
            if child.height > 0 {
                total += dp(child.height) + dp(child.margin.1) + dp(child.margin.3)
            } else {
                total += 48
            }
        }
        return max(total, maxH)
    }

    /// Solved position and size for a child within the ConstraintLayout
    struct SolvedPosition {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var width: CGFloat? = nil
        var height: CGFloat? = nil
        var maxWidth: CGFloat? = nil
        var maxHeight: CGFloat? = nil
    }

    private func solveChild(_ child: RenderNode, parentSize: CGSize) -> SolvedPosition {
        let c = child.constraints
        let parentW = parentSize.width
        let parentH = parentSize.height
        let marginL = dp(child.margin.0)
        let marginT = dp(child.margin.1)
        let marginR = dp(child.margin.2)
        let marginB = dp(child.margin.3)

        var result = SolvedPosition()

        // Determine child intrinsic width
        let childW: CGFloat? = child.width > 0 ? dp(child.width) : nil
        let childH: CGFloat? = child.height > 0 ? dp(child.height) : nil

        // --- Horizontal axis ---
        let leftEdge = resolveLeftEdge(c, parentW: parentW)
        let rightEdge = resolveRightEdge(c, parentW: parentW)

        if c.isCenteredH {
            // Constrained on both sides
            if let le = leftEdge, let re = rightEdge {
                let availableW = re - le - marginL - marginR
                if child.width == 0 || child.width == -1 {
                    // match_constraint (0dp) or match_parent: stretch to fill
                    result.x = le + marginL
                    result.width = max(availableW, 0)
                } else if let cw = childW {
                    // Fixed size: center with bias
                    let slack = availableW - cw
                    result.x = le + marginL + slack * CGFloat(c.horizontalBias)
                    result.width = cw
                } else {
                    // wrap_content: center with bias
                    // We don't know intrinsic width, so use maxWidth and let SwiftUI handle it
                    result.x = le + marginL
                    result.maxWidth = max(availableW, 0)
                    // Adjust with bias by offsetting: for default 0.5 bias, center
                    // For wrap_content centered, just center in the available space
                }
            }
        } else if c.isLeftOnly {
            if let le = leftEdge {
                result.x = le + marginL
            }
            if let cw = childW { result.width = cw }
        } else if c.isRightOnly {
            if let re = rightEdge {
                if let cw = childW {
                    result.x = re - marginR - cw
                    result.width = cw
                } else {
                    // wrap_content aligned right - approximate
                    result.x = max(re - marginR - 100, 0)
                }
            }
        } else {
            // No horizontal constraints - default to left edge
            result.x = marginL
            if let cw = childW { result.width = cw }
        }

        // --- Vertical axis ---
        let topEdge = resolveTopEdge(c, parentH: parentH)
        let bottomEdge = resolveBottomEdge(c, parentH: parentH)

        if c.isCenteredV {
            if let te = topEdge, let be = bottomEdge {
                let availableH = be - te - marginT - marginB
                if child.height == 0 || child.height == -1 {
                    // match_constraint or match_parent: stretch
                    result.y = te + marginT
                    result.height = max(availableH, 0)
                } else if let ch = childH {
                    let slack = availableH - ch
                    result.y = te + marginT + slack * CGFloat(c.verticalBias)
                    result.height = ch
                } else {
                    result.y = te + marginT
                    result.maxHeight = max(availableH, 0)
                }
            }
        } else if c.isTopOnly {
            if let te = topEdge {
                result.y = te + marginT
            }
            if let ch = childH { result.height = ch }
        } else if c.isBottomOnly {
            if let be = bottomEdge {
                if let ch = childH {
                    result.y = be - marginB - ch
                    result.height = ch
                } else {
                    result.y = max(be - marginB - 48, 0)
                }
            }
        } else {
            // No vertical constraints - default to top
            result.y = marginT
            if let ch = childH { result.height = ch }
        }

        return result
    }

    /// Resolve the left anchor edge position in parent coordinates
    private func resolveLeftEdge(_ c: ConstraintAnchors, parentW: CGFloat) -> CGFloat? {
        if c.leftToLeft == kConstraintParent { return 0 }
        if c.leftToRight == kConstraintParent { return parentW }
        if c.leftToLeft != 0 {
            // Anchored to left edge of sibling - find sibling's right boundary
            // For simplicity, treat sibling constraints as approximate center positions
            return findSiblingLeftEdge(c.leftToLeft)
        }
        if c.leftToRight != 0 {
            return findSiblingRightEdge(c.leftToRight)
        }
        return nil
    }

    private func resolveRightEdge(_ c: ConstraintAnchors, parentW: CGFloat) -> CGFloat? {
        if c.rightToRight == kConstraintParent { return parentW }
        if c.rightToLeft == kConstraintParent { return 0 }
        if c.rightToRight != 0 {
            return findSiblingRightEdge(c.rightToRight)
        }
        if c.rightToLeft != 0 {
            return findSiblingLeftEdge(c.rightToLeft)
        }
        return nil
    }

    private func resolveTopEdge(_ c: ConstraintAnchors, parentH: CGFloat) -> CGFloat? {
        if c.topToTop == kConstraintParent { return 0 }
        if c.topToBottom == kConstraintParent { return parentH }
        if c.topToTop != 0 {
            return findSiblingTopEdge(c.topToTop)
        }
        if c.topToBottom != 0 {
            return findSiblingBottomEdge(c.topToBottom)
        }
        return nil
    }

    private func resolveBottomEdge(_ c: ConstraintAnchors, parentH: CGFloat) -> CGFloat? {
        if c.bottomToBottom == kConstraintParent { return parentH }
        if c.bottomToTop == kConstraintParent { return 0 }
        if c.bottomToBottom != 0 {
            return findSiblingBottomEdge(c.bottomToBottom)
        }
        if c.bottomToTop != 0 {
            return findSiblingTopEdge(c.bottomToTop)
        }
        return nil
    }

    // MARK: - Guideline position resolution

    /// Compute a guideline's position in parent coordinates
    private func guidelinePosition(_ guideline: RenderNode, parentSize: CGSize) -> CGFloat {
        if guideline.guidelineOrientation == 1 {
            // Vertical guideline: provides an X position
            if guideline.guidelinePercent >= 0 {
                return parentSize.width * CGFloat(guideline.guidelinePercent)
            } else if guideline.guidelineBegin >= 0 {
                return dp(Int32(guideline.guidelineBegin))
            }
            return 0
        } else {
            // Horizontal guideline: provides a Y position
            if guideline.guidelinePercent >= 0 {
                return parentSize.height * CGFloat(guideline.guidelinePercent)
            } else if guideline.guidelineBegin >= 0 {
                return dp(Int32(guideline.guidelineBegin))
            }
            return 0
        }
    }

    // MARK: - Sibling edge estimation
    // For sibling-to-sibling constraints, we do a simplified single-pass estimation.
    // We estimate sibling positions based on their own constraints to parent only.
    // This handles the most common chains (A→parent, B→A's bottom, etc.)
    // Guidelines are resolved by computing their fixed position.

    private func findSiblingLeftEdge(_ viewId: UInt32) -> CGFloat? {
        guard let sibling = node.children.first(where: { $0.viewId == viewId }) else { return nil }
        // If sibling is a guideline, return its computed position
        if sibling.isGuideline {
            // Vertical guideline provides a left/right edge (X position)
            if sibling.guidelineOrientation == 1 {
                // Need parent size; estimate from node width or use 0
                // We don't have parentSize here, so use percent * estimated width
                return guidelinePositionEstimate(sibling, isHorizontalAxis: true)
            }
            return nil
        }
        return dp(sibling.margin.0)
    }

    private func findSiblingRightEdge(_ viewId: UInt32) -> CGFloat? {
        guard let sibling = node.children.first(where: { $0.viewId == viewId }) else { return nil }
        if sibling.isGuideline {
            if sibling.guidelineOrientation == 1 {
                return guidelinePositionEstimate(sibling, isHorizontalAxis: true)
            }
            return nil
        }
        let w: CGFloat = sibling.width > 0 ? dp(sibling.width) : 100 // estimate
        return dp(sibling.margin.0) + w
    }

    private func findSiblingTopEdge(_ viewId: UInt32) -> CGFloat? {
        guard let sibling = node.children.first(where: { $0.viewId == viewId }) else { return nil }
        if sibling.isGuideline {
            if sibling.guidelineOrientation == 0 {
                return guidelinePositionEstimate(sibling, isHorizontalAxis: false)
            }
            return nil
        }
        // If sibling is constrained to parent top, its top is its top margin
        if sibling.constraints.topToTop == kConstraintParent {
            return dp(sibling.margin.1)
        }
        // If sibling is constrained below another sibling, estimate recursively (1 level)
        if sibling.constraints.topToBottom != 0 && sibling.constraints.topToBottom != kConstraintParent {
            if let aboveBottom = findSiblingBottomEdge(sibling.constraints.topToBottom) {
                return aboveBottom + dp(sibling.margin.1)
            }
        }
        return dp(sibling.margin.1)
    }

    private func findSiblingBottomEdge(_ viewId: UInt32) -> CGFloat? {
        guard let sibling = node.children.first(where: { $0.viewId == viewId }) else { return nil }
        if sibling.isGuideline {
            if sibling.guidelineOrientation == 0 {
                return guidelinePositionEstimate(sibling, isHorizontalAxis: false)
            }
            return nil
        }
        let h: CGFloat = sibling.height > 0 ? dp(sibling.height) : 48 // estimate
        if let top = findSiblingTopEdge(viewId) {
            return top + h + dp(sibling.margin.3)
        }
        return dp(sibling.margin.1) + h + dp(sibling.margin.3)
    }

    /// Estimate guideline position without parent size (uses node's own dimensions as fallback)
    private func guidelinePositionEstimate(_ gl: RenderNode, isHorizontalAxis: Bool) -> CGFloat {
        if gl.guidelineBegin >= 0 {
            return dp(Int32(gl.guidelineBegin))
        }
        if gl.guidelinePercent >= 0 {
            // Estimate parent dimension from node width/height
            let parentDim: CGFloat
            if isHorizontalAxis {
                parentDim = node.width > 0 ? dp(node.width) : 390 // iPhone default
            } else {
                parentDim = node.height > 0 ? dp(node.height) : 844
            }
            return parentDim * CGFloat(gl.guidelinePercent)
        }
        return 0
    }

    // MARK: - Chain detection and rendering

    /// A chain is a sequence of views linked left-to-right (horizontal) or top-to-bottom (vertical)
    struct Chain {
        let members: [RenderNode]
        let style: UInt8  // 0=none/spread, 1=spread, 2=spread_inside, 3=packed
    }

    /// Detect horizontal chains among children
    private func detectHorizontalChains() -> [Chain] {
        var chains: [Chain] = []
        var visited = Set<UInt32>()

        for child in node.children where !child.isGuideline && !visited.contains(child.viewId) {
            // A chain head has h_chain_style set OR is the leftmost in a mutual constraint sequence
            guard child.constraints.hChainStyle != 0 else { continue }

            // Walk the chain: follow left_to_right / right_to_left links
            var members: [RenderNode] = [child]
            visited.insert(child.viewId)

            // Walk forward: find views whose left is constrained to current view's right
            var currentId = child.viewId
            while true {
                if let next = node.children.first(where: {
                    !visited.contains($0.viewId) &&
                    !$0.isGuideline &&
                    ($0.constraints.leftToRight == currentId)
                }) {
                    members.append(next)
                    visited.insert(next.viewId)
                    currentId = next.viewId
                } else {
                    break
                }
            }

            if members.count > 1 {
                chains.append(Chain(members: members, style: child.constraints.hChainStyle))
            } else {
                // Single view with chain style set but no chain found - remove from visited
                // so it renders normally
                visited.remove(child.viewId)
            }
        }
        return chains
    }

    /// Detect vertical chains among children
    private func detectVerticalChains() -> [Chain] {
        var chains: [Chain] = []
        var visited = Set<UInt32>()

        for child in node.children where !child.isGuideline && !visited.contains(child.viewId) {
            guard child.constraints.vChainStyle != 0 else { continue }

            var members: [RenderNode] = [child]
            visited.insert(child.viewId)

            var currentId = child.viewId
            while true {
                if let next = node.children.first(where: {
                    !visited.contains($0.viewId) &&
                    !$0.isGuideline &&
                    ($0.constraints.topToBottom == currentId)
                }) {
                    members.append(next)
                    visited.insert(next.viewId)
                    currentId = next.viewId
                } else {
                    break
                }
            }

            if members.count > 1 {
                chains.append(Chain(members: members, style: child.constraints.vChainStyle))
            } else {
                visited.remove(child.viewId)
            }
        }
        return chains
    }

    /// Collect all view IDs that belong to any chain (so they are not rendered individually)
    private func collectChainMemberIds(hChains: [Chain], vChains: [Chain]) -> Set<UInt32> {
        var ids = Set<UInt32>()
        for chain in hChains {
            for m in chain.members { ids.insert(m.viewId) }
        }
        for chain in vChains {
            for m in chain.members { ids.insert(m.viewId) }
        }
        return ids
    }

    /// Solved chain member position
    struct ChainMemberPosition {
        let index: Int
        let x: CGFloat
        let y: CGFloat
    }

    /// Compute x positions for a horizontal chain
    private func solveHorizontalChainPositions(_ chain: Chain, parentSize: CGSize) -> (yPos: CGFloat, positions: [CGFloat]) {
        let parentW = parentSize.width
        let first = chain.members[0]
        let c = first.constraints

        let topEdge = resolveTopEdge(c, parentH: parentSize.height)
        let yPos = (topEdge ?? 0) + dp(first.margin.1)

        let leftBound = resolveLeftEdge(c, parentW: parentW) ?? 0
        let lastC = chain.members[chain.members.count - 1].constraints
        let rightBound = resolveRightEdge(lastC, parentW: parentW) ?? parentW
        let availableW = rightBound - leftBound

        let totalChildW: CGFloat = chain.members.reduce(0) { sum, m in
            let w: CGFloat = m.width > 0 ? dp(m.width) : 80
            return sum + w + dp(m.margin.0) + dp(m.margin.2)
        }

        let remainingSpace = max(availableW - totalChildW, 0)
        let count = CGFloat(chain.members.count)

        var xPositions: [CGFloat] = []

        if chain.style == 2 {
            // spread_inside
            let gap = count > 1 ? remainingSpace / (count - 1) : 0
            var x = leftBound
            for (i, m) in chain.members.enumerated() {
                xPositions.append(x + dp(m.margin.0))
                let w: CGFloat = m.width > 0 ? dp(m.width) : 80
                x += dp(m.margin.0) + w + dp(m.margin.2)
                if i < chain.members.count - 1 { x += gap }
            }
        } else if chain.style == 3 {
            // packed
            let bias = CGFloat(first.constraints.horizontalBias)
            let startX = leftBound + remainingSpace * bias
            var x = startX
            for m in chain.members {
                xPositions.append(x + dp(m.margin.0))
                let w: CGFloat = m.width > 0 ? dp(m.width) : 80
                x += dp(m.margin.0) + w + dp(m.margin.2)
            }
        } else {
            // spread (default, style 1 or 0)
            let gap = count > 0 ? remainingSpace / (count + 1) : 0
            var x = leftBound + gap
            for m in chain.members {
                xPositions.append(x + dp(m.margin.0))
                let w: CGFloat = m.width > 0 ? dp(m.width) : 80
                x += dp(m.margin.0) + w + dp(m.margin.2) + gap
            }
        }

        return (yPos, xPositions)
    }

    /// Compute y positions for a vertical chain
    private func solveVerticalChainPositions(_ chain: Chain, parentSize: CGSize) -> (xPos: CGFloat, positions: [CGFloat]) {
        let parentH = parentSize.height
        let first = chain.members[0]
        let c = first.constraints

        let leftEdge = resolveLeftEdge(c, parentW: parentSize.width)
        let xPos = (leftEdge ?? 0) + dp(first.margin.0)

        let topBound = resolveTopEdge(c, parentH: parentH) ?? 0
        let lastC = chain.members[chain.members.count - 1].constraints
        let bottomBound = resolveBottomEdge(lastC, parentH: parentH) ?? parentH
        let availableH = bottomBound - topBound

        let totalChildH: CGFloat = chain.members.reduce(0) { sum, m in
            let h: CGFloat = m.height > 0 ? dp(m.height) : 48
            return sum + h + dp(m.margin.1) + dp(m.margin.3)
        }

        let remainingSpace = max(availableH - totalChildH, 0)
        let count = CGFloat(chain.members.count)

        var yPositions: [CGFloat] = []

        if chain.style == 2 {
            // spread_inside
            let gap = count > 1 ? remainingSpace / (count - 1) : 0
            var y = topBound
            for (i, m) in chain.members.enumerated() {
                yPositions.append(y + dp(m.margin.1))
                let h: CGFloat = m.height > 0 ? dp(m.height) : 48
                y += dp(m.margin.1) + h + dp(m.margin.3)
                if i < chain.members.count - 1 { y += gap }
            }
        } else if chain.style == 3 {
            // packed
            let bias = CGFloat(first.constraints.verticalBias)
            let startY = topBound + remainingSpace * bias
            var y = startY
            for m in chain.members {
                yPositions.append(y + dp(m.margin.1))
                let h: CGFloat = m.height > 0 ? dp(m.height) : 48
                y += dp(m.margin.1) + h + dp(m.margin.3)
            }
        } else {
            // spread (default)
            let gap = count > 0 ? remainingSpace / (count + 1) : 0
            var y = topBound + gap
            for m in chain.members {
                yPositions.append(y + dp(m.margin.1))
                let h: CGFloat = m.height > 0 ? dp(m.height) : 48
                y += dp(m.margin.1) + h + dp(m.margin.3) + gap
            }
        }

        return (xPos, yPositions)
    }

    /// Render a horizontal chain using the specified distribution style
    @ViewBuilder
    private func renderHorizontalChain(_ chain: Chain, parentSize: CGSize) -> some View {
        let solved = solveHorizontalChainPositions(chain, parentSize: parentSize)

        ForEach(Array(chain.members.enumerated()), id: \.element.id) { idx, member in
            let xPos = idx < solved.positions.count ? solved.positions[idx] : 0
            let w: CGFloat? = member.width > 0 ? dp(member.width) : nil
            let h: CGFloat? = member.height > 0 ? dp(member.height) : nil
            AndroidViewRenderer(node: member, bridge: bridge)
                .frame(width: w, height: h)
                .alignmentGuide(.leading) { _ in -xPos }
                .alignmentGuide(.top) { _ in -solved.yPos }
        }
    }

    /// Render a vertical chain using the specified distribution style
    @ViewBuilder
    private func renderVerticalChain(_ chain: Chain, parentSize: CGSize) -> some View {
        let solved = solveVerticalChainPositions(chain, parentSize: parentSize)

        ForEach(Array(chain.members.enumerated()), id: \.element.id) { idx, member in
            let yP = idx < solved.positions.count ? solved.positions[idx] : 0
            let w: CGFloat? = member.width > 0 ? dp(member.width) : nil
            let h: CGFloat? = member.height > 0 ? dp(member.height) : nil
            AndroidViewRenderer(node: member, bridge: bridge)
                .frame(width: w, height: h)
                .alignmentGuide(.leading) { _ in -solved.xPos }
                .alignmentGuide(.top) { _ in -yP }
        }
    }
}

// MARK: - EditText interactive view

private struct EditTextFieldView: View {
    let initialText: String
    let hint: String
    let textSize: CGFloat
    let inputType: UInt32
    let viewId: UInt32
    let bridge: RuntimeBridge

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    /// Whether this is a password field (inputType 0x81 = textPassword, 0x12 = numberPassword, 0x91 = textVisiblePassword)
    private var isPassword: Bool {
        inputType == 0x81 || inputType == 0x12 || inputType == 0x91
    }

    /// Keyboard type based on Android inputType value
    private var keyboardType: UIKeyboardType {
        switch inputType {
        case 0x02: return .numberPad           // number
        case 0x21: return .emailAddress         // textEmailAddress
        case 0x11: return .URL                  // textUri
        case 0x03: return .phonePad             // phone
        case 0x2002: return .decimalPad         // numberDecimal
        default: return .default
        }
    }

    var body: some View {
        Group {
            if isPassword {
                SecureField(hint, text: $text)
                    .font(.system(size: max(textSize, 1)))
            } else {
                TextField(hint, text: $text)
                    .font(.system(size: max(textSize, 1)))
                    .keyboardType(keyboardType)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isFocused ? Color.blue : Color.gray.opacity(0.4), lineWidth: isFocused ? 2 : 1)
        )
        .focused($isFocused)
        .onAppear { text = initialText }
        .onChange(of: text) { _, newValue in
            bridge.updateEditText(viewId: viewId, text: newValue)
        }
    }
}

// MARK: - WKWebView wrapper for android.webkit.WebView

private struct WebViewWrapper: UIViewRepresentable {
    let url: String?
    let html: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.isScrollEnabled = true
        loadContent(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload content when URL or HTML changes
        loadContent(into: webView)
    }

    private func loadContent(into webView: WKWebView) {
        if let html = html, !html.isEmpty {
            webView.loadHTMLString(html, baseURL: nil)
        } else if let urlString = url, !urlString.isEmpty,
                  let parsedURL = URL(string: urlString) {
            webView.load(URLRequest(url: parsedURL))
        } else {
            // No content specified - show blank page with placeholder
            let placeholder = """
            <html><body style="display:flex;align-items:center;justify-content:center;\
            height:100vh;margin:0;font-family:-apple-system;color:#999;">\
            <div style="text-align:center"><div style="font-size:48px">&#127760;</div>\
            <div>WebView</div></div></body></html>
            """
            webView.loadHTMLString(placeholder, baseURL: nil)
        }
    }
}

// MARK: - Canvas draw command renderer

/// Renders Android Canvas draw commands using SwiftUI's Canvas view
private struct CanvasDrawView: View {
    let commands: [DrawCommand]
    let node: RenderNode

    var body: some View {
        Canvas { context, size in
            for cmd in commands {
                switch cmd.type {
                case DX_DRAW_COLOR:
                    // Fill entire canvas with color
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(argbColor(cmd.color)))

                case DX_DRAW_RECT:
                    let rect = CGRect(
                        x: CGFloat(cmd.params.0),
                        y: CGFloat(cmd.params.1),
                        width: CGFloat(cmd.params.2 - cmd.params.0),
                        height: CGFloat(cmd.params.3 - cmd.params.1)
                    )
                    let path = Path(rect)
                    drawPath(context: &context, path: path, cmd: cmd)

                case DX_DRAW_CIRCLE:
                    let cx = CGFloat(cmd.params.0)
                    let cy = CGFloat(cmd.params.1)
                    let r = CGFloat(cmd.params.2)
                    let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                    let path = Path(ellipseIn: rect)
                    drawPath(context: &context, path: path, cmd: cmd)

                case DX_DRAW_LINE:
                    var path = Path()
                    path.move(to: CGPoint(x: CGFloat(cmd.params.0), y: CGFloat(cmd.params.1)))
                    path.addLine(to: CGPoint(x: CGFloat(cmd.params.2), y: CGFloat(cmd.params.3)))
                    let sw = max(CGFloat(cmd.strokeWidth), 1.0)
                    context.stroke(path, with: .color(argbColor(cmd.color)),
                                   lineWidth: sw)

                case DX_DRAW_TEXT:
                    if let text = cmd.text {
                        let fontSize = max(CGFloat(cmd.textSize), 1.0)
                        let resolved = context.resolve(
                            Text(text)
                                .font(.system(size: fontSize))
                                .foregroundColor(argbColor(cmd.color))
                        )
                        let point = CGPoint(x: CGFloat(cmd.params.0),
                                            y: CGFloat(cmd.params.1) - fontSize)
                        context.draw(resolved, at: point, anchor: .topLeading)
                    }

                case DX_DRAW_ROUND_RECT:
                    let rect = CGRect(
                        x: CGFloat(cmd.params.0),
                        y: CGFloat(cmd.params.1),
                        width: CGFloat(cmd.params.2 - cmd.params.0),
                        height: CGFloat(cmd.params.3 - cmd.params.1)
                    )
                    let rx = CGFloat(cmd.params.4)
                    let ry = CGFloat(cmd.params.5)
                    let cornerSize = CGSize(width: rx, height: ry)
                    let path = Path(roundedRect: rect, cornerSize: cornerSize)
                    drawPath(context: &context, path: path, cmd: cmd)

                case DX_DRAW_OVAL:
                    let rect = CGRect(
                        x: CGFloat(cmd.params.0),
                        y: CGFloat(cmd.params.1),
                        width: CGFloat(cmd.params.2 - cmd.params.0),
                        height: CGFloat(cmd.params.3 - cmd.params.1)
                    )
                    let path = Path(ellipseIn: rect)
                    drawPath(context: &context, path: path, cmd: cmd)

                case DX_DRAW_SAVE:
                    break // SwiftUI Canvas does not support save/restore stack
                case DX_DRAW_RESTORE:
                    break
                case DX_DRAW_TRANSLATE:
                    break // Transform recording; would need state tracking
                case DX_DRAW_ROTATE:
                    break
                case DX_DRAW_SCALE:
                    break

                default:
                    break
                }
            }
        }
        .frame(
            width: canvasWidth,
            height: canvasHeight
        )
    }

    /// Determine canvas dimensions from the node's explicit size or a default
    private var canvasWidth: CGFloat? {
        if node.width > 0 { return CGFloat(node.width) }
        return nil  // let SwiftUI decide
    }

    private var canvasHeight: CGFloat? {
        if node.height > 0 { return CGFloat(node.height) }
        // Estimate from draw commands bounding box
        var maxY: Float = 100
        for cmd in commands {
            switch cmd.type {
            case DX_DRAW_RECT, DX_DRAW_ROUND_RECT, DX_DRAW_OVAL:
                maxY = max(maxY, cmd.params.3) // bottom
            case DX_DRAW_CIRCLE:
                maxY = max(maxY, cmd.params.1 + cmd.params.2) // cy + r
            case DX_DRAW_LINE:
                maxY = max(maxY, max(cmd.params.1, cmd.params.3))
            case DX_DRAW_TEXT:
                maxY = max(maxY, cmd.params.1 + cmd.textSize)
            default:
                break
            }
        }
        return CGFloat(maxY)
    }

    /// Draw a path with fill and/or stroke based on paint style
    private func drawPath(context: inout GraphicsContext, path: Path, cmd: DrawCommand) {
        let color = argbColor(cmd.color)
        let sw = max(CGFloat(cmd.strokeWidth), 1.0)

        switch cmd.paintStyle {
        case 1: // STROKE
            context.stroke(path, with: .color(color), lineWidth: sw)
        case 2: // FILL_AND_STROKE
            context.fill(path, with: .color(color))
            context.stroke(path, with: .color(color), lineWidth: sw)
        default: // 0 = FILL
            context.fill(path, with: .color(color))
        }
    }
}

// MARK: - Vector drawable renderer

/// Renders an Android VectorDrawable using SwiftUI Path from SVG path data
private struct VectorDrawableView: View {
    let pathData: String
    let fillColor: UInt32
    let strokeColor: UInt32
    let strokeWidth: Float
    let viewportWidth: Float
    let viewportHeight: Float

    var body: some View {
        let vpW = CGFloat(max(viewportWidth, 1))
        let vpH = CGFloat(max(viewportHeight, 1))
        let parsed = SVGPathParser.parse(pathData)

        Canvas { context, size in
            // Scale from viewport to rendered size, preserving aspect ratio
            let scaleX = size.width / vpW
            let scaleY = size.height / vpH
            let scale = min(scaleX, scaleY)
            let offsetX = (size.width - vpW * scale) / 2
            let offsetY = (size.height - vpH * scale) / 2

            // Build a scaled path
            var path = Path()
            for cmd in parsed {
                switch cmd {
                case .moveTo(let x, let y):
                    path.move(to: CGPoint(x: x * scale + offsetX, y: y * scale + offsetY))
                case .lineTo(let x, let y):
                    path.addLine(to: CGPoint(x: x * scale + offsetX, y: y * scale + offsetY))
                case .cubicTo(let x1, let y1, let x2, let y2, let x, let y):
                    path.addCurve(
                        to: CGPoint(x: x * scale + offsetX, y: y * scale + offsetY),
                        control1: CGPoint(x: x1 * scale + offsetX, y: y1 * scale + offsetY),
                        control2: CGPoint(x: x2 * scale + offsetX, y: y2 * scale + offsetY)
                    )
                case .quadTo(let x1, let y1, let x, let y):
                    path.addQuadCurve(
                        to: CGPoint(x: x * scale + offsetX, y: y * scale + offsetY),
                        control: CGPoint(x: x1 * scale + offsetX, y: y1 * scale + offsetY)
                    )
                case .arcTo(let rx, let ry, let rotation, let largeArc, let sweep, let x, let y):
                    addArc(to: &path, rx: rx * scale, ry: ry * scale,
                           rotation: rotation, largeArc: largeArc, sweep: sweep,
                           endX: x * scale + offsetX, endY: y * scale + offsetY)
                case .close:
                    path.closeSubpath()
                case .horizontalTo(let x):
                    let cur = path.currentPoint ?? .zero
                    path.addLine(to: CGPoint(x: x * scale + offsetX, y: cur.y))
                case .verticalTo(let y):
                    let cur = path.currentPoint ?? .zero
                    path.addLine(to: CGPoint(x: cur.x, y: y * scale + offsetY))
                }
            }

            // Fill
            let fc = argbColor(fillColor)
            context.fill(path, with: .color(fc))

            // Stroke
            if strokeColor != 0 && strokeWidth > 0 {
                let sc = argbColor(strokeColor)
                context.stroke(path, with: .color(sc), lineWidth: CGFloat(strokeWidth) * scale)
            }
        }
        .aspectRatio(vpW / vpH, contentMode: .fit)
    }

    /// Approximate SVG arc with cubic bezier curves
    private func addArc(to path: inout Path, rx: CGFloat, ry: CGFloat,
                        rotation: CGFloat, largeArc: Bool, sweep: Bool,
                        endX: CGFloat, endY: CGFloat) {
        let cur = path.currentPoint ?? .zero
        // Degenerate cases
        if rx == 0 || ry == 0 {
            path.addLine(to: CGPoint(x: endX, y: endY))
            return
        }
        if cur.x == endX && cur.y == endY { return }

        // Use endpoint parameterization -> center parameterization conversion
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (cur.x - endX) / 2
        let dy = (cur.y - endY) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        var rxAbs = abs(rx)
        var ryAbs = abs(ry)

        // Scale radii if necessary
        let lambda = (x1p * x1p) / (rxAbs * rxAbs) + (y1p * y1p) / (ryAbs * ryAbs)
        if lambda > 1 {
            let sqrtLambda = sqrt(lambda)
            rxAbs *= sqrtLambda
            ryAbs *= sqrtLambda
        }

        let rxSq = rxAbs * rxAbs
        let rySq = ryAbs * ryAbs
        let x1pSq = x1p * x1p
        let y1pSq = y1p * y1p

        var sq = max(0, (rxSq * rySq - rxSq * y1pSq - rySq * x1pSq) / (rxSq * y1pSq + rySq * x1pSq))
        sq = sqrt(sq) * (largeArc == sweep ? -1 : 1)

        let cxp = sq * rxAbs * y1p / ryAbs
        let cyp = -sq * ryAbs * x1p / rxAbs

        let cx = cosPhi * cxp - sinPhi * cyp + (cur.x + endX) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (cur.y + endY) / 2

        let theta1 = angle(ux: 1, uy: 0, vx: (x1p - cxp) / rxAbs, vy: (y1p - cyp) / ryAbs)
        var dTheta = angle(ux: (x1p - cxp) / rxAbs, uy: (y1p - cyp) / ryAbs,
                           vx: (-x1p - cxp) / rxAbs, vy: (-y1p - cyp) / ryAbs)

        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        // Approximate arc with cubic bezier segments (max 90 degrees each)
        let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let segAngle = dTheta / CGFloat(segments)

        for i in 0..<segments {
            let t1 = theta1 + CGFloat(i) * segAngle
            let t2 = t1 + segAngle
            arcSegment(path: &path, cx: cx, cy: cy, rx: rxAbs, ry: ryAbs,
                       phi: phi, t1: t1, t2: t2)
        }
    }

    private func angle(ux: CGFloat, uy: CGFloat, vx: CGFloat, vy: CGFloat) -> CGFloat {
        let dot = ux * vx + uy * vy
        let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
        var a = acos(max(-1, min(1, dot / max(len, 1e-10))))
        if ux * vy - uy * vx < 0 { a = -a }
        return a
    }

    private func arcSegment(path: inout Path, cx: CGFloat, cy: CGFloat,
                            rx: CGFloat, ry: CGFloat, phi: CGFloat,
                            t1: CGFloat, t2: CGFloat) {
        let alpha = sin(t2 - t1) * (sqrt(4 + 3 * pow(tan((t2 - t1) / 2), 2)) - 1) / 3
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        func point(_ t: CGFloat) -> CGPoint {
            let ct = cos(t), st = sin(t)
            return CGPoint(
                x: cx + cosPhi * rx * ct - sinPhi * ry * st,
                y: cy + sinPhi * rx * ct + cosPhi * ry * st
            )
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            let ct = cos(t), st = sin(t)
            return CGPoint(
                x: -cosPhi * rx * st - sinPhi * ry * ct,
                y: -sinPhi * rx * st + cosPhi * ry * ct
            )
        }

        let p1 = point(t1)
        let p2 = point(t2)
        let d1 = derivative(t1)
        let d2 = derivative(t2)

        let cp1 = CGPoint(x: p1.x + alpha * d1.x, y: p1.y + alpha * d1.y)
        let cp2 = CGPoint(x: p2.x - alpha * d2.x, y: p2.y - alpha * d2.y)

        path.addCurve(to: p2, control1: cp1, control2: cp2)
    }
}

// MARK: - SVG path data parser

/// Parsed SVG path command (all coordinates are absolute)
private enum SVGPathCommand {
    case moveTo(CGFloat, CGFloat)
    case lineTo(CGFloat, CGFloat)
    case horizontalTo(CGFloat)
    case verticalTo(CGFloat)
    case cubicTo(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    case quadTo(CGFloat, CGFloat, CGFloat, CGFloat)
    case arcTo(CGFloat, CGFloat, CGFloat, Bool, Bool, CGFloat, CGFloat)  // rx,ry,rot,large,sweep,x,y
    case close
}

/// Parser for SVG path data strings (M, L, C, Q, Z, H, V, A, S, T and lowercase relative variants)
private struct SVGPathParser {
    static func parse(_ data: String) -> [SVGPathCommand] {
        var commands: [SVGPathCommand] = []
        var scanner = PathScanner(data)
        var curX: CGFloat = 0
        var curY: CGFloat = 0
        var startX: CGFloat = 0
        var startY: CGFloat = 0
        var lastCp2X: CGFloat = 0  // for smooth curves
        var lastCp2Y: CGFloat = 0
        var lastCmd: Character = " "

        while !scanner.isAtEnd {
            scanner.skipWhitespaceAndCommas()
            if scanner.isAtEnd { break }

            var cmd = scanner.peekChar()
            let isLetter = cmd.isLetter
            if isLetter {
                scanner.advance()
            } else {
                // Implicit repeat of last command
                cmd = lastCmd
            }

            let isRelative = cmd.isLowercase
            let cmdUpper = Character(String(cmd).uppercased())

            switch cmdUpper {
            case "M":
                var first = true
                while let x = scanner.nextNumber() {
                    scanner.skipCommaOrWhitespace()
                    guard let y = scanner.nextNumber() else { break }
                    let ax = isRelative ? curX + x : x
                    let ay = isRelative ? curY + y : y
                    if first {
                        commands.append(.moveTo(ax, ay))
                        startX = ax; startY = ay
                        first = false
                    } else {
                        commands.append(.lineTo(ax, ay))
                    }
                    curX = ax; curY = ay
                    lastCp2X = curX; lastCp2Y = curY
                }
                lastCmd = isRelative ? "l" : "L"  // subsequent coords are lineTo

            case "L":
                while let x = scanner.nextNumber() {
                    scanner.skipCommaOrWhitespace()
                    guard let y = scanner.nextNumber() else { break }
                    let ax = isRelative ? curX + x : x
                    let ay = isRelative ? curY + y : y
                    commands.append(.lineTo(ax, ay))
                    curX = ax; curY = ay
                    lastCp2X = curX; lastCp2Y = curY
                }
                lastCmd = cmd

            case "H":
                while let x = scanner.nextNumber() {
                    let ax = isRelative ? curX + x : x
                    commands.append(.horizontalTo(ax))
                    curX = ax
                    lastCp2X = curX; lastCp2Y = curY
                }
                lastCmd = cmd

            case "V":
                while let y = scanner.nextNumber() {
                    let ay = isRelative ? curY + y : y
                    commands.append(.verticalTo(ay))
                    curY = ay
                    lastCp2X = curX; lastCp2Y = curY
                }
                lastCmd = cmd

            case "C":
                while let x1 = scanner.nextNumber() {
                    scanner.skipCommaOrWhitespace()
                    guard let y1 = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let x2 = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let y2 = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let x = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let y = scanner.nextNumber() else { break }
                    let ax1 = isRelative ? curX + x1 : x1
                    let ay1 = isRelative ? curY + y1 : y1
                    let ax2 = isRelative ? curX + x2 : x2
                    let ay2 = isRelative ? curY + y2 : y2
                    let ax = isRelative ? curX + x : x
                    let ay = isRelative ? curY + y : y
                    commands.append(.cubicTo(ax1, ay1, ax2, ay2, ax, ay))
                    lastCp2X = ax2; lastCp2Y = ay2
                    curX = ax; curY = ay
                }
                lastCmd = cmd

            case "S":
                // Smooth cubic: reflect last control point
                while let x2 = scanner.nextNumber() {
                    scanner.skipCommaOrWhitespace()
                    guard let y2 = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let x = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let y = scanner.nextNumber() else { break }
                    let ax1 = 2 * curX - lastCp2X
                    let ay1 = 2 * curY - lastCp2Y
                    let ax2 = isRelative ? curX + x2 : x2
                    let ay2 = isRelative ? curY + y2 : y2
                    let ax = isRelative ? curX + x : x
                    let ay = isRelative ? curY + y : y
                    commands.append(.cubicTo(ax1, ay1, ax2, ay2, ax, ay))
                    lastCp2X = ax2; lastCp2Y = ay2
                    curX = ax; curY = ay
                }
                lastCmd = cmd

            case "Q":
                while let x1 = scanner.nextNumber() {
                    scanner.skipCommaOrWhitespace()
                    guard let y1 = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let x = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let y = scanner.nextNumber() else { break }
                    let ax1 = isRelative ? curX + x1 : x1
                    let ay1 = isRelative ? curY + y1 : y1
                    let ax = isRelative ? curX + x : x
                    let ay = isRelative ? curY + y : y
                    commands.append(.quadTo(ax1, ay1, ax, ay))
                    lastCp2X = ax1; lastCp2Y = ay1
                    curX = ax; curY = ay
                }
                lastCmd = cmd

            case "T":
                // Smooth quad: reflect last control point
                while let x = scanner.nextNumber() {
                    scanner.skipCommaOrWhitespace()
                    guard let y = scanner.nextNumber() else { break }
                    let ax1 = 2 * curX - lastCp2X
                    let ay1 = 2 * curY - lastCp2Y
                    let ax = isRelative ? curX + x : x
                    let ay = isRelative ? curY + y : y
                    commands.append(.quadTo(ax1, ay1, ax, ay))
                    lastCp2X = ax1; lastCp2Y = ay1
                    curX = ax; curY = ay
                }
                lastCmd = cmd

            case "A":
                while let rx = scanner.nextNumber() {
                    scanner.skipCommaOrWhitespace()
                    guard let ry = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let rotation = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let largeArcVal = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let sweepVal = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let x = scanner.nextNumber() else { break }
                    scanner.skipCommaOrWhitespace()
                    guard let y = scanner.nextNumber() else { break }
                    let ax = isRelative ? curX + x : x
                    let ay = isRelative ? curY + y : y
                    commands.append(.arcTo(rx, ry, rotation, largeArcVal != 0, sweepVal != 0, ax, ay))
                    curX = ax; curY = ay
                    lastCp2X = curX; lastCp2Y = curY
                }
                lastCmd = cmd

            case "Z":
                commands.append(.close)
                curX = startX; curY = startY
                lastCp2X = curX; lastCp2Y = curY
                lastCmd = cmd

            default:
                // Unknown command, skip
                scanner.advance()
            }
        }

        return commands
    }
}

/// Simple character-based scanner for SVG path data
private struct PathScanner {
    private let chars: [Character]
    private var index: Int

    init(_ string: String) {
        self.chars = Array(string)
        self.index = 0
    }

    var isAtEnd: Bool { index >= chars.count }

    func peekChar() -> Character {
        guard index < chars.count else { return "\0" }
        return chars[index]
    }

    mutating func advance() {
        if index < chars.count { index += 1 }
    }

    mutating func skipWhitespaceAndCommas() {
        while index < chars.count && (chars[index] == " " || chars[index] == "," ||
                                       chars[index] == "\t" || chars[index] == "\n" ||
                                       chars[index] == "\r") {
            index += 1
        }
    }

    mutating func skipCommaOrWhitespace() {
        skipWhitespaceAndCommas()
    }

    /// Parse the next number (integer or decimal, possibly negative)
    mutating func nextNumber() -> CGFloat? {
        skipWhitespaceAndCommas()
        guard index < chars.count else { return nil }

        // Check if the next token looks like a number
        let c = chars[index]
        guard c == "-" || c == "+" || c == "." || c.isNumber else { return nil }

        var numStr = ""
        // Sign
        if index < chars.count && (chars[index] == "-" || chars[index] == "+") {
            numStr.append(chars[index])
            index += 1
        }
        // Integer part
        while index < chars.count && chars[index].isNumber {
            numStr.append(chars[index])
            index += 1
        }
        // Decimal part
        if index < chars.count && chars[index] == "." {
            numStr.append(".")
            index += 1
            while index < chars.count && chars[index].isNumber {
                numStr.append(chars[index])
                index += 1
            }
        }
        // Exponent
        if index < chars.count && (chars[index] == "e" || chars[index] == "E") {
            numStr.append(chars[index])
            index += 1
            if index < chars.count && (chars[index] == "-" || chars[index] == "+") {
                numStr.append(chars[index])
                index += 1
            }
            while index < chars.count && chars[index].isNumber {
                numStr.append(chars[index])
                index += 1
            }
        }

        guard !numStr.isEmpty, numStr != "-", numStr != "+", numStr != "." else { return nil }
        return CGFloat(Double(numStr) ?? 0)
    }
}
