import Foundation
import Combine
import UIKit

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: String
    let tag: String
    let message: String
}

// MARK: - DEX Browser Models

struct DEXClassInfo: Identifiable, Hashable {
    let id = UUID()
    let classDefIndex: UInt32
    let name: String
    let accessFlags: UInt32
    let methodCount: Int
    let fieldCount: Int

    var displayName: String {
        // Convert "Lcom/example/Foo;" to "com.example.Foo"
        var n = name
        if n.hasPrefix("L") && n.hasSuffix(";") {
            n = String(n.dropFirst().dropLast())
        }
        return n.replacingOccurrences(of: "/", with: ".")
    }

    var accessFlagsText: String {
        accessFlagsString(accessFlags, isClass: true)
    }
}

struct DEXMethodInfo: Identifiable {
    let id = UUID()
    let name: String
    let descriptor: String
    let accessFlags: UInt32
    let registerCount: Int
    let codeSize: Int

    var accessFlagsText: String {
        accessFlagsString(accessFlags, isClass: false)
    }
}

struct DEXFieldInfo: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let accessFlags: UInt32

    var accessFlagsText: String {
        accessFlagsString(accessFlags, isClass: false)
    }
}

struct DEXClassDetail {
    let methods: [DEXMethodInfo]
    let fields: [DEXFieldInfo]
}

// MARK: - Manifest Models

struct ManifestInfo {
    let packageName: String
    let mainActivity: String
    let minSdk: Int32
    let targetSdk: Int32
    let appLabel: String
    let appTheme: String
    let activities: [ManifestComponentInfo]
    let services: [ManifestComponentInfo]
    let receivers: [ManifestComponentInfo]
    let providers: [ManifestComponentInfo]
    let permissions: [String]
    let features: [ManifestFeatureInfo]
}

struct ManifestComponentInfo: Identifiable {
    let id = UUID()
    let name: String
    let exported: Bool
    let intentFilters: [ManifestIntentFilterInfo]
}

struct ManifestIntentFilterInfo: Identifiable {
    let id = UUID()
    let actions: [String]
    let categories: [String]
}

struct ManifestFeatureInfo {
    let name: String
    let required: Bool
}

// MARK: - Resource Resolution Models

struct ResourceResolution: Identifiable {
    let id = UUID()
    let resourceId: UInt32
    let type: String           // e.g., "string", "color", "dimen"
    let qualifiers: String     // config qualifiers description
    let resolvedValue: String  // formatted resolved value
    let configUsed: String     // which config matched
}

struct ResourceEntry: Identifiable {
    let id = UUID()
    let resourceId: UInt32
    let name: String
    let type: String
    let value: String
}

// MARK: - Access Flags Helper

private func accessFlagsString(_ flags: UInt32, isClass: Bool) -> String {
    var parts: [String] = []
    if flags & 0x0001 != 0 { parts.append("public") }
    if flags & 0x0002 != 0 { parts.append("private") }
    if flags & 0x0004 != 0 { parts.append("protected") }
    if flags & 0x0008 != 0 { parts.append("static") }
    if flags & 0x0010 != 0 { parts.append("final") }
    if flags & 0x0020 != 0 && !isClass { parts.append("synchronized") }
    if flags & 0x0100 != 0 { parts.append("native") }
    if flags & 0x0200 != 0 { parts.append("interface") }
    if flags & 0x0400 != 0 { parts.append("abstract") }
    if flags & 0x4000 != 0 { parts.append("enum") }
    return parts.joined(separator: " ")
}

/// ConstraintLayout constraint anchors for a child view
struct ConstraintAnchors {
    let leftToLeft: UInt32      // 0 = none, 0xFFFFFFFF = parent, else view ID
    let leftToRight: UInt32
    let rightToRight: UInt32
    let rightToLeft: UInt32
    let topToTop: UInt32
    let topToBottom: UInt32
    let bottomToBottom: UInt32
    let bottomToTop: UInt32
    let horizontalBias: Float   // 0.0-1.0, default 0.5
    let verticalBias: Float
    let hChainStyle: UInt8      // 0=none, 1=spread, 2=spread_inside, 3=packed
    let vChainStyle: UInt8      // 0=none, 1=spread, 2=spread_inside, 3=packed

    var hasHorizontal: Bool {
        let hasLeft = leftToLeft != 0 || leftToRight != 0
        let hasRight = rightToRight != 0 || rightToLeft != 0
        return hasLeft || hasRight
    }
    var hasVertical: Bool {
        let hasTop = topToTop != 0 || topToBottom != 0
        let hasBottom = bottomToBottom != 0 || bottomToTop != 0
        return hasTop || hasBottom
    }
    /// True if constrained on both left and right (centered or stretched)
    var isCenteredH: Bool {
        let hasLeft = leftToLeft != 0 || leftToRight != 0
        let hasRight = rightToRight != 0 || rightToLeft != 0
        return hasLeft && hasRight
    }
    /// True if constrained on both top and bottom
    var isCenteredV: Bool {
        let hasTop = topToTop != 0 || topToBottom != 0
        let hasBottom = bottomToBottom != 0 || bottomToTop != 0
        return hasTop && hasBottom
    }
    /// True if only left/start constrained (no right)
    var isLeftOnly: Bool {
        let hasLeft = leftToLeft != 0 || leftToRight != 0
        let hasRight = rightToRight != 0 || rightToLeft != 0
        return hasLeft && !hasRight
    }
    /// True if only right/end constrained (no left)
    var isRightOnly: Bool {
        let hasLeft = leftToLeft != 0 || leftToRight != 0
        let hasRight = rightToRight != 0 || rightToLeft != 0
        return !hasLeft && hasRight
    }
    /// True if only top constrained (no bottom)
    var isTopOnly: Bool {
        let hasTop = topToTop != 0 || topToBottom != 0
        let hasBottom = bottomToBottom != 0 || bottomToTop != 0
        return hasTop && !hasBottom
    }
    /// True if only bottom constrained (no top)
    var isBottomOnly: Bool {
        let hasTop = topToTop != 0 || topToBottom != 0
        let hasBottom = bottomToBottom != 0 || bottomToTop != 0
        return !hasTop && hasBottom
    }
    var hasAny: Bool { hasHorizontal || hasVertical }
}

/// A single recorded Canvas draw command, mirroring C DxDrawCommand
struct DrawCommand: Identifiable {
    let id = UUID()
    let type: DxDrawCmdType
    let params: (Float, Float, Float, Float, Float, Float)
    let color: UInt32
    let strokeWidth: Float
    let paintStyle: Int32   // 0=FILL, 1=STROKE, 2=FILL_AND_STROKE
    let textSize: Float
    let text: String?
}

/// Shape drawable background properties (parsed from shape XML)
struct ShapeBackground {
    let shapeType: UInt8       // 0=rectangle, 1=oval, 2=line, 3=ring
    let solidColor: UInt32     // ARGB
    let cornerRadius: Float    // dp
    let strokeWidth: Float     // dp
    let strokeColor: UInt32    // ARGB
    let gradientStart: UInt32  // ARGB
    let gradientEnd: UInt32    // ARGB
    let gradientType: UInt8    // 0=linear, 1=radial, 2=sweep
}

struct RenderNode: Identifiable {
    let id = UUID()
    let type: DxViewType
    let viewId: UInt32
    let text: String?
    let hint: String?
    let orientation: DxOrientation
    let textSize: Float
    let width: Int32       // -1 = match_parent, -2 = wrap_content
    let height: Int32      // -1 = match_parent, -2 = wrap_content
    let weight: Float      // layout_weight (0 = none)
    let gravity: Int32
    let padding: (Int32, Int32, Int32, Int32)
    let margin: (Int32, Int32, Int32, Int32)
    let bgColor: UInt32
    let textColor: UInt32
    let isChecked: Bool
    let inputType: UInt32         // android:inputType value
    let scaleType: UInt8          // 0=fitCenter, 1=center, 2=centerCrop, 3=centerInside, 4=fitXY, 5=fitStart, 6=fitEnd
    let visibility: DxVisibility  // VISIBLE=0, INVISIBLE=4, GONE=8
    let hasClickListener: Bool
    let hasLongClickListener: Bool
    let hasRefreshListener: Bool
    let relativeFlags: UInt16     // RelativeLayout positioning bit flags
    let relAbove: UInt32          // layout_above view ID
    let relBelow: UInt32          // layout_below view ID
    let relLeftOf: UInt32         // layout_toLeftOf view ID
    let relRightOf: UInt32        // layout_toRightOf view ID
    let constraints: ConstraintAnchors  // ConstraintLayout constraints
    let isGuideline: Bool              // true if this is a ConstraintLayout guideline
    let guidelineOrientation: UInt8    // 0=horizontal, 1=vertical
    let guidelinePercent: Float        // 0.0-1.0, or -1 if using begin
    let guidelineBegin: Float          // dp offset from start, or -1
    let imageData: Data?          // PNG/JPEG bytes for ImageView
    let isNinePatch: Bool         // true if image is a compiled 9-patch PNG
    let ninePatchPadding: (Int32, Int32, Int32, Int32)   // left, top, right, bottom content padding
    let ninePatchStretchX: (Int32, Int32)                // start, end of horizontal stretch region
    let ninePatchStretchY: (Int32, Int32)                // start, end of vertical stretch region
    let vectorPathData: String?   // SVG path data for vector drawable
    let vectorFillColor: UInt32   // ARGB fill color for vector drawable
    let vectorStrokeColor: UInt32 // ARGB stroke color for vector drawable
    let vectorStrokeWidth: Float  // stroke width for vector drawable
    let vectorWidth: Float        // viewport width for vector drawable
    let vectorHeight: Float       // viewport height for vector drawable
    let shapeBg: ShapeBackground?  // Shape drawable background
    let webURL: String?           // URL for WebView
    let webHTML: String?          // HTML content for WebView
    let alpha: Float               // 0.0-1.0 (default 1.0)
    let rotation: Float            // degrees (default 0)
    let scaleX: Float              // scale factor (default 1.0)
    let scaleY: Float              // scale factor (default 1.0)
    let translationX: Float        // dp offset (default 0)
    let translationY: Float        // dp offset (default 0)
    let measuredWidth: Float         // resolved width in dp (0 = not measured)
    let measuredHeight: Float        // resolved height in dp (0 = not measured)
    let focusable: Bool              // true if view can receive focus
    let focused: Bool                // true if view currently has focus
    let drawCommands: [DrawCommand]  // Canvas draw commands
    let children: [RenderNode]
}

@MainActor
final class RuntimeBridge: ObservableObject {
    @Published var logs: [LogEntry] = []
    @Published var renderTree: RenderNode?
    @Published var isLoaded = false
    @Published var isRunning = false
    @Published var isExecuting = false   // true while interpreter is actively running on background thread
    @Published var errorMessage: String?
    @Published var packageName: String?
    @Published var activityName: String?
    @Published var apkEntries: [String] = []
    @Published var dexClassCount: UInt32 = 0
    @Published var dexMethodCount: UInt32 = 0
    @Published var dexStringCount: UInt32 = 0

    private var context: UnsafeMutablePointer<DxContext>?
    // Throttle log delivery to avoid flooding the main thread
    private var pendingLogs: [(String, String, String)] = []
    private var logFlushScheduled = false
    private static let maxLogs = 1000
    private var memoryWarningObserver: NSObjectProtocol?

    // Throttle render model refreshes to ~60fps (16ms minimum interval)
    private var lastRenderRefresh: CFAbsoluteTime = 0
    private static let minRenderInterval: CFAbsoluteTime = 0.016 // 16ms
    private var deferredRenderScheduled = false

    init() {
        addLog(level: "INFO", tag: "Bridge", message: "DexLoom runtime bridge initialized")
        RuntimeBridge.setupNetworkBridge()

        // Register for iOS memory pressure warnings
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let ctx = self.context, let vm = ctx.pointee.vm else { return }
            self.addLog(level: "WARN", tag: "Bridge", message: "Memory warning received — forcing GC")
            dx_vm_gc_collect(vm)
        }
    }

    /// Install the C-to-Swift network callback for real HTTP requests via URLSession
    private static func setupNetworkBridge() {
        dx_runtime_set_network_callback { (request: UnsafePointer<DxNetworkRequest>?) -> DxNetworkResponse in
            guard let request = request, let urlCStr = request.pointee.url else {
                return DxNetworkResponse(status_code: -1, body: nil, body_size: 0,
                                         header_names: nil, header_values: nil, header_count: 0)
            }

            let urlString = String(cString: urlCStr)
            guard let url = URL(string: urlString) else {
                return DxNetworkResponse(status_code: -1, body: nil, body_size: 0,
                                         header_names: nil, header_values: nil, header_count: 0)
            }

            var urlRequest = URLRequest(url: url)

            // Set HTTP method
            if let methodPtr = request.pointee.method {
                urlRequest.httpMethod = String(cString: methodPtr)
            }

            // Set request headers
            let headerCount = Int(request.pointee.header_count)
            if headerCount > 0,
               let names = request.pointee.header_names,
               let values = request.pointee.header_values {
                for i in 0..<headerCount {
                    if let namePtr = names[i], let valPtr = values[i] {
                        let name = String(cString: namePtr)
                        let value = String(cString: valPtr)
                        urlRequest.setValue(value, forHTTPHeaderField: name)
                    }
                }
            }

            // Set request body
            if request.pointee.body_size > 0, let bodyPtr = request.pointee.body {
                urlRequest.httpBody = Data(bytes: bodyPtr, count: request.pointee.body_size)
            }

            // Perform synchronous request using semaphore
            let semaphore = DispatchSemaphore(value: 0)
            var responseData: Data?
            var httpResponse: HTTPURLResponse?

            let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                responseData = data
                httpResponse = response as? HTTPURLResponse
                semaphore.signal()
            }
            task.resume()
            semaphore.wait()

            // Build C response
            let statusCode = Int32(httpResponse?.statusCode ?? -1)

            // Copy response body
            var bodyPtr: UnsafeMutablePointer<UInt8>? = nil
            var bodySize: Int = 0
            if let data = responseData, !data.isEmpty {
                bodySize = data.count
                bodyPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: bodySize)
                data.copyBytes(to: bodyPtr!, count: bodySize)
            }

            // Copy response headers
            var hdrNamesPtrPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = nil
            var hdrValuesPtrPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = nil
            var hdrCount: Int32 = 0

            if let allHeaders = httpResponse?.allHeaderFields as? [String: String], !allHeaders.isEmpty {
                let count = allHeaders.count
                hdrCount = Int32(count)
                hdrNamesPtrPtr = .allocate(capacity: count)
                hdrValuesPtrPtr = .allocate(capacity: count)
                var idx = 0
                for (key, value) in allHeaders {
                    hdrNamesPtrPtr![idx] = strdup(key)
                    hdrValuesPtrPtr![idx] = strdup(value)
                    idx += 1
                }
            }

            return DxNetworkResponse(
                status_code: statusCode,
                body: bodyPtr,
                body_size: bodySize,
                header_names: hdrNamesPtrPtr,
                header_values: hdrValuesPtrPtr,
                header_count: hdrCount
            )
        }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let ctx = context {
            dx_runtime_shutdown(ctx)
        }
    }

    func loadAPK(at url: URL) {
        let path = url.path

        addLog(level: "INFO", tag: "Bridge", message: "Loading APK: \(url.lastPathComponent)")

        // Create context
        guard let ctx = dx_context_create() else {
            errorMessage = "Failed to create runtime context"
            addLog(level: "ERROR", tag: "Bridge", message: "dx_context_create failed")
            return
        }
        self.context = ctx

        // Set log level to INFO to suppress TRACE/DEBUG flooding
        dx_log_set_level(DX_LOG_INFO)

        // Set up log callback - batch logs to prevent MainActor queue flooding
        let bridge = Unmanaged.passUnretained(self).toOpaque()
        dx_log_set_callback({ level, tag, message, userData in
            guard let userData = userData else { return }
            let bridge = Unmanaged<RuntimeBridge>.fromOpaque(userData).takeUnretainedValue()
            let levelStr: String
            switch level {
            case DX_LOG_TRACE: levelStr = "TRACE"
            case DX_LOG_DEBUG: levelStr = "DEBUG"
            case DX_LOG_INFO:  levelStr = "INFO"
            case DX_LOG_WARN:  levelStr = "WARN"
            case DX_LOG_ERROR: levelStr = "ERROR"
            default:           levelStr = "?"
            }
            let tagStr = tag.map { String(cString: $0) } ?? "?"
            let msgStr = message.map { String(cString: $0) } ?? ""

            // Batch log delivery to avoid creating thousands of Task closures
            Task { @MainActor in
                bridge.enqueuLog(level: levelStr, tag: tagStr, message: msgStr)
            }
        }, bridge)

        // Set up UI update callback
        ctx.pointee.on_ui_update = { model, userData in
            guard let userData = userData, let model = model else { return }
            let bridge = Unmanaged<RuntimeBridge>.fromOpaque(userData).takeUnretainedValue()
            let tree = RuntimeBridge.convertRenderModel(model.pointee.root)
            Task { @MainActor in
                bridge.renderTree = tree
            }
        }
        ctx.pointee.ui_callback_data = bridge

        // Load APK on background thread
        Task.detached { [weak self] in
            let result = dx_context_load_apk(ctx, path)

            await MainActor.run {
                guard let self = self else { return }
                if result == DX_OK {
                    self.isLoaded = true
                    self.packageName = ctx.pointee.package_name.map { String(cString: $0) }
                    self.activityName = ctx.pointee.main_activity_class.map { String(cString: $0) }
                    if let dex = ctx.pointee.dex {
                        self.dexClassCount = dex.pointee.class_count
                        self.dexMethodCount = dex.pointee.method_count
                        self.dexStringCount = dex.pointee.string_count
                    }
                    self.addLog(level: "INFO", tag: "Bridge", message: "APK loaded successfully")
                } else {
                    let errStr = String(cString: dx_result_string(result))
                    self.errorMessage = "Load failed: \(errStr)"
                    self.addLog(level: "ERROR", tag: "Bridge", message: "Load failed: \(errStr)")
                }
            }
        }
    }

    func run() {
        guard let ctx = context, isLoaded, !isRunning else {
            if isRunning { return }  // prevent re-entry
            errorMessage = "No APK loaded"
            return
        }

        isRunning = true      // set immediately to prevent multiple taps
        isExecuting = true    // show loading indicator while interpreter runs
        addLog(level: "INFO", tag: "Bridge", message: "Starting runtime execution")

        // Clear any previous cancellation flag
        if let vm = ctx.pointee.vm {
            vm.pointee.cancel_requested = false
        }

        Task.detached { [weak self] in
            let result = dx_context_run(ctx)

            await MainActor.run {
                guard let self = self else { return }
                self.isExecuting = false  // interpreter finished

                if result == DX_OK {
                    self.addLog(level: "INFO", tag: "Bridge", message: "Runtime started successfully")
                    // Build initial render tree
                    self.refreshRenderTree(from: ctx, force: true)
                    if self.renderTree != nil {
                        self.addLog(level: "INFO", tag: "Bridge", message: "Render model found, building tree")
                        self.addLog(level: "INFO", tag: "Bridge", message: "Render tree built: type=\(self.renderTree!.type.rawValue), children=\(self.renderTree!.children.count)")
                    } else {
                        self.addLog(level: "WARN", tag: "Bridge", message: "No render model available (setContentView may not have been called)")
                    }
                } else if result == DX_ERR_CANCELLED {
                    self.isRunning = false
                    self.addLog(level: "INFO", tag: "Bridge", message: "Execution cancelled by user")
                } else {
                    self.isRunning = false
                    let errStr = String(cString: dx_result_string(result))
                    self.errorMessage = "Run failed: \(errStr)"
                    self.addLog(level: "ERROR", tag: "Bridge", message: "Run failed: \(errStr)")
                    if let vm = ctx.pointee.vm {
                        let vmErr = withUnsafePointer(to: &vm.pointee.error_msg) { ptr -> String in
                            ptr.withMemoryRebound(to: CChar.self, capacity: 256) { cptr in
                                // Ensure null termination by checking within bounds
                                var len = 0
                                while len < 255 && cptr[len] != 0 { len += 1 }
                                if len == 0 { return "" }
                                return String(bytes: UnsafeBufferPointer(start: UnsafePointer<UInt8>(OpaquePointer(cptr)), count: len), encoding: .utf8) ?? ""
                            }
                        }
                        if !vmErr.isEmpty {
                            self.addLog(level: "ERROR", tag: "VM", message: vmErr)
                        }
                    }
                }
            }
        }
    }

    /// Request cancellation of the currently executing interpreter.
    /// The interpreter checks this flag every 10000 instructions and stops gracefully.
    func cancelExecution() {
        guard let ctx = context, let vm = ctx.pointee.vm, isExecuting else { return }
        addLog(level: "INFO", tag: "Bridge", message: "Cancellation requested")
        vm.pointee.cancel_requested = true
    }

    /// Refresh render tree with 60fps throttle. Skips if less than 16ms since last refresh
    /// unless `force` is true (used for initial build).
    /// When an update is skipped due to throttle, a deferred update is scheduled 16ms later
    /// to ensure the final state in a burst of updates is always rendered.
    private func refreshRenderTree(from ctx: UnsafeMutablePointer<DxContext>, force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        if !force && (now - lastRenderRefresh) < RuntimeBridge.minRenderInterval {
            // Schedule a deferred render so the final update in a burst is never lost
            if !deferredRenderScheduled {
                deferredRenderScheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + RuntimeBridge.minRenderInterval) { [weak self] in
                    guard let self = self else { return }
                    self.deferredRenderScheduled = false
                    if let model = dx_runtime_get_render_model(ctx) {
                        self.renderTree = RuntimeBridge.convertRenderModel(model.pointee.root)
                        self.lastRenderRefresh = CFAbsoluteTimeGetCurrent()
                    }
                }
            }
            return
        }
        if let model = dx_runtime_get_render_model(ctx) {
            self.renderTree = RuntimeBridge.convertRenderModel(model.pointee.root)
            lastRenderRefresh = now
        }
    }

    func dispatchClick(viewId: UInt32) {
        guard let ctx = context else { return }
        addLog(level: "DEBUG", tag: "Bridge", message: "Click on view 0x\(String(viewId, radix: 16))")

        Task.detached { [weak self] in
            let result = dx_runtime_dispatch_click(ctx, viewId)

            await MainActor.run {
                guard let self = self else { return }
                if result != DX_OK {
                    let errStr = String(cString: dx_result_string(result))
                    self.addLog(level: "WARN", tag: "Bridge", message: "Click dispatch failed: \(errStr)")
                }
                // Refresh render tree (throttled)
                self.refreshRenderTree(from: ctx)
            }
        }
    }

    func dispatchLongClick(viewId: UInt32) {
        guard let ctx = context else { return }
        addLog(level: "DEBUG", tag: "Bridge", message: "Long-click on view 0x\(String(viewId, radix: 16))")

        Task.detached { [weak self] in
            let result = dx_runtime_dispatch_long_click(ctx, viewId)

            await MainActor.run {
                guard let self = self else { return }
                if result != DX_OK {
                    let errStr = String(cString: dx_result_string(result))
                    self.addLog(level: "WARN", tag: "Bridge", message: "Long-click dispatch failed: \(errStr)")
                }
                // Refresh render tree (throttled)
                self.refreshRenderTree(from: ctx)
            }
        }
    }

    func dispatchRefresh(viewId: UInt32) {
        guard let ctx = context else { return }
        addLog(level: "DEBUG", tag: "Bridge", message: "Refresh on view 0x\(String(viewId, radix: 16))")

        Task.detached { [weak self] in
            let result = dx_runtime_dispatch_refresh(ctx, viewId)

            await MainActor.run {
                guard let self = self else { return }
                if result != DX_OK {
                    let errStr = String(cString: dx_result_string(result))
                    self.addLog(level: "WARN", tag: "Bridge", message: "Refresh dispatch failed: \(errStr)")
                }
                // Refresh render tree (throttled)
                self.refreshRenderTree(from: ctx)
            }
        }
    }

    func updateEditText(viewId: UInt32, text: String) {
        guard let ctx = context else { return }
        text.withCString { cStr in
            dx_runtime_update_edit_text(ctx, viewId, cStr)
        }
    }

    func dispatchBack() {
        guard let ctx = context else { return }
        addLog(level: "DEBUG", tag: "Bridge", message: "Back button pressed")

        Task.detached { [weak self] in
            let result = dx_runtime_dispatch_back(ctx)

            await MainActor.run {
                guard let self = self else { return }
                if result != DX_OK {
                    let errStr = String(cString: dx_result_string(result))
                    self.addLog(level: "WARN", tag: "Bridge", message: "Back dispatch failed: \(errStr)")
                }
                // Refresh render tree (throttled)
                self.refreshRenderTree(from: ctx)
            }
        }
    }

    func shutdown() {
        // If interpreter is still running, request cancellation first
        if isExecuting, let ctx = context, let vm = ctx.pointee.vm {
            vm.pointee.cancel_requested = true
        }
        if let ctx = context {
            dx_runtime_shutdown(ctx)
            context = nil
        }
        isLoaded = false
        isRunning = false
        isExecuting = false
        renderTree = nil
    }

    // MARK: - Inspector Data

    /// Get all DEX classes with summary info
    func getDEXClasses() -> [DEXClassInfo] {
        guard let ctx = context, let dex = ctx.pointee.dex else { return [] }
        var result: [DEXClassInfo] = []
        let count = Int(dex.pointee.class_count)

        for i in 0..<count {
            let classDef = dex.pointee.class_defs.advanced(by: i).pointee
            let className = dx_dex_get_type(dex, classDef.class_idx).map { String(cString: $0) } ?? "?"

            // Parse class data to get method/field counts
            var methodCount = 0
            var fieldCount = 0
            if classDef.class_data_off != 0 {
                let parseResult = dx_dex_parse_class_data(dex, UInt32(i))
                if parseResult == DX_OK, let cd = dex.pointee.class_data.advanced(by: i).pointee {
                    methodCount = Int(cd.pointee.direct_methods_count + cd.pointee.virtual_methods_count)
                    fieldCount = Int(cd.pointee.static_fields_count + cd.pointee.instance_fields_count)
                }
            }

            result.append(DEXClassInfo(
                classDefIndex: UInt32(i),
                name: className,
                accessFlags: classDef.access_flags,
                methodCount: methodCount,
                fieldCount: fieldCount
            ))
        }

        return result
    }

    /// Get detailed class info (methods and fields) by class def index
    func getDEXClassDetail(index: UInt32) -> DEXClassDetail? {
        guard let ctx = context, let dex = ctx.pointee.dex else { return nil }
        guard index < dex.pointee.class_count else { return nil }

        let classDef = dex.pointee.class_defs.advanced(by: Int(index)).pointee
        guard classDef.class_data_off != 0 else {
            return DEXClassDetail(methods: [], fields: [])
        }

        let parseResult = dx_dex_parse_class_data(dex, index)
        guard parseResult == DX_OK, let cd = dex.pointee.class_data.advanced(by: Int(index)).pointee else {
            return DEXClassDetail(methods: [], fields: [])
        }

        var methods: [DEXMethodInfo] = []

        // Direct methods
        for j in 0..<Int(cd.pointee.direct_methods_count) {
            let em = cd.pointee.direct_methods.advanced(by: j).pointee
            let info = buildMethodInfo(dex: dex, encodedMethod: em)
            methods.append(info)
        }

        // Virtual methods
        for j in 0..<Int(cd.pointee.virtual_methods_count) {
            let em = cd.pointee.virtual_methods.advanced(by: j).pointee
            let info = buildMethodInfo(dex: dex, encodedMethod: em)
            methods.append(info)
        }

        var fields: [DEXFieldInfo] = []

        // Static fields
        for j in 0..<Int(cd.pointee.static_fields_count) {
            let ef = cd.pointee.static_fields.advanced(by: j).pointee
            let info = buildFieldInfo(dex: dex, encodedField: ef)
            fields.append(info)
        }

        // Instance fields
        for j in 0..<Int(cd.pointee.instance_fields_count) {
            let ef = cd.pointee.instance_fields.advanced(by: j).pointee
            let info = buildFieldInfo(dex: dex, encodedField: ef)
            fields.append(info)
        }

        return DEXClassDetail(methods: methods, fields: fields)
    }

    private func buildMethodInfo(dex: UnsafeMutablePointer<DxDexFile>, encodedMethod: DxDexEncodedMethod) -> DEXMethodInfo {
        let name = dx_dex_get_method_name(dex, encodedMethod.method_idx).map { String(cString: $0) } ?? "?"
        let returnType = dx_dex_get_method_return_type(dex, encodedMethod.method_idx).map { String(cString: $0) } ?? "V"

        // Build descriptor from params + return type
        var paramTypes: [String] = []
        let paramCount = dx_dex_get_method_param_count(dex, encodedMethod.method_idx)
        for p in 0..<paramCount {
            if let pt = dx_dex_get_method_param_type(dex, encodedMethod.method_idx, p) {
                paramTypes.append(String(cString: pt))
            }
        }
        let descriptor = "(\(paramTypes.joined(separator: ", "))) -> \(returnType)"

        var regCount = 0
        var codeSize = 0
        if encodedMethod.code_off != 0 {
            var codeItem = DxDexCodeItem()
            if dx_dex_parse_code_item(dex, encodedMethod.code_off, &codeItem) == DX_OK {
                regCount = Int(codeItem.registers_size)
                codeSize = Int(codeItem.insns_size)
                dx_dex_free_code_item(&codeItem)
            }
        }

        return DEXMethodInfo(
            name: name,
            descriptor: descriptor,
            accessFlags: encodedMethod.access_flags,
            registerCount: regCount,
            codeSize: codeSize
        )
    }

    private func buildFieldInfo(dex: UnsafeMutablePointer<DxDexFile>, encodedField: DxDexEncodedField) -> DEXFieldInfo {
        let name = dx_dex_get_field_name(dex, encodedField.field_idx).map { String(cString: $0) } ?? "?"
        let fieldId = dex.pointee.field_ids.advanced(by: Int(encodedField.field_idx)).pointee
        let fieldType = dx_dex_get_type(dex, UInt32(fieldId.type_idx)).map { String(cString: $0) } ?? "?"

        return DEXFieldInfo(
            name: name,
            type: fieldType,
            accessFlags: encodedField.access_flags
        )
    }

    /// Parse manifest from the loaded APK
    func getManifestInfo() -> ManifestInfo? {
        guard let ctx = context, let apkOpaque = ctx.pointee.apk else { return nil }
        // Cast from OpaquePointer (struct DxApkFile *) to typed pointer (typedef DxApkFile *)
        let apk = UnsafePointer<DxApkFile>(apkOpaque)

        // Find and extract AndroidManifest.xml
        var entryPtr: UnsafePointer<DxZipEntry>?
        guard dx_apk_find_entry(apk, "AndroidManifest.xml", &entryPtr) == DX_OK,
              let entry = entryPtr else { return nil }

        var dataPtr: UnsafeMutablePointer<UInt8>?
        var dataSize: UInt32 = 0
        guard dx_apk_extract_entry(apk, entry, &dataPtr, &dataSize) == DX_OK,
              let data = dataPtr else { return nil }
        defer { dx_free(data) }

        var manifestPtr: UnsafeMutablePointer<DxManifest>?
        guard dx_manifest_parse(data, dataSize, &manifestPtr) == DX_OK,
              let manifest = manifestPtr else { return nil }
        defer { dx_manifest_free(manifest) }

        let m = manifest.pointee

        // Build activities
        var activities: [ManifestComponentInfo] = []
        for i in 0..<Int(m.activity_component_count) {
            let comp = m.activity_components.advanced(by: i).pointee
            activities.append(buildComponentInfo(comp))
        }
        // If no rich components, fall back to name list
        if activities.isEmpty {
            for i in 0..<Int(m.activity_count) {
                if let namePtr = m.activities.advanced(by: i).pointee {
                    activities.append(ManifestComponentInfo(
                        name: String(cString: namePtr),
                        exported: false,
                        intentFilters: []
                    ))
                }
            }
        }

        // Build services
        var services: [ManifestComponentInfo] = []
        for i in 0..<Int(m.service_component_count) {
            let comp = m.service_components.advanced(by: i).pointee
            services.append(buildComponentInfo(comp))
        }
        if services.isEmpty {
            for i in 0..<Int(m.service_count) {
                if let namePtr = m.services.advanced(by: i).pointee {
                    services.append(ManifestComponentInfo(
                        name: String(cString: namePtr),
                        exported: false,
                        intentFilters: []
                    ))
                }
            }
        }

        // Build receivers
        var receivers: [ManifestComponentInfo] = []
        for i in 0..<Int(m.receiver_component_count) {
            let comp = m.receiver_components.advanced(by: i).pointee
            receivers.append(buildComponentInfo(comp))
        }
        if receivers.isEmpty {
            for i in 0..<Int(m.receiver_count) {
                if let namePtr = m.receivers.advanced(by: i).pointee {
                    receivers.append(ManifestComponentInfo(
                        name: String(cString: namePtr),
                        exported: false,
                        intentFilters: []
                    ))
                }
            }
        }

        // Build providers
        var providers: [ManifestComponentInfo] = []
        for i in 0..<Int(m.provider_component_count) {
            let comp = m.provider_components.advanced(by: i).pointee
            providers.append(buildComponentInfo(comp))
        }
        if providers.isEmpty {
            for i in 0..<Int(m.provider_count) {
                if let namePtr = m.providers.advanced(by: i).pointee {
                    providers.append(ManifestComponentInfo(
                        name: String(cString: namePtr),
                        exported: false,
                        intentFilters: []
                    ))
                }
            }
        }

        // Permissions
        var permissions: [String] = []
        for i in 0..<Int(m.permission_count) {
            if let namePtr = m.permissions.advanced(by: i).pointee {
                permissions.append(String(cString: namePtr))
            }
        }

        // Features
        var features: [ManifestFeatureInfo] = []
        for i in 0..<Int(m.feature_count) {
            let f = m.features.advanced(by: i).pointee
            let name = f.name.map { String(cString: $0) } ?? "?"
            features.append(ManifestFeatureInfo(name: name, required: f.required))
        }

        return ManifestInfo(
            packageName: m.package_name.map { String(cString: $0) } ?? "unknown",
            mainActivity: m.main_activity.map { String(cString: $0) } ?? "",
            minSdk: m.min_sdk,
            targetSdk: m.target_sdk,
            appLabel: m.app_label.map { String(cString: $0) } ?? "",
            appTheme: m.app_theme.map { String(cString: $0) } ?? "",
            activities: activities,
            services: services,
            receivers: receivers,
            providers: providers,
            permissions: permissions,
            features: features
        )
    }

    private func buildComponentInfo(_ comp: DxComponent) -> ManifestComponentInfo {
        let name = comp.name.map { String(cString: $0) } ?? "?"

        var filters: [ManifestIntentFilterInfo] = []
        for i in 0..<Int(comp.intent_filter_count) {
            let f = comp.intent_filters.advanced(by: i).pointee
            var actions: [String] = []
            for j in 0..<Int(f.action_count) {
                if let ptr = f.actions.advanced(by: j).pointee {
                    actions.append(String(cString: ptr))
                }
            }
            var categories: [String] = []
            for j in 0..<Int(f.category_count) {
                if let ptr = f.categories.advanced(by: j).pointee {
                    categories.append(String(cString: ptr))
                }
            }
            filters.append(ManifestIntentFilterInfo(actions: actions, categories: categories))
        }

        return ManifestComponentInfo(
            name: name,
            exported: comp.exported,
            intentFilters: filters
        )
    }

    // MARK: - Resource Inspector

    /// Resolve a resource by ID and return resolution metadata
    func resolveResource(id: UInt32) -> ResourceResolution? {
        guard let ctx = context, let res = ctx.pointee.resources else { return nil }

        let entry = dx_resources_find_by_id(res, id)
        guard let e = entry else { return nil }

        let typeName: String
        if let tn = e.pointee.type_name {
            typeName = String(cString: tn)
        } else {
            typeName = resourceTypeName(for: e.pointee.value_type)
        }

        let entryName: String
        if let en = e.pointee.entry_name {
            entryName = String(cString: en)
        } else {
            entryName = String(format: "0x%08X", id)
        }

        let resolvedValue = formatResourceValue(e.pointee)
        let qualifiers = formatResConfig(e.pointee.config)
        let configUsed = qualifiers.isEmpty ? "default" : qualifiers

        return ResourceResolution(
            resourceId: id,
            type: typeName,
            qualifiers: qualifiers.isEmpty ? "default (no qualifiers)" : qualifiers,
            resolvedValue: "\(entryName) = \(resolvedValue)",
            configUsed: configUsed
        )
    }

    /// Get all resource entries (for the resource list)
    func getAllResourceEntries() -> [ResourceEntry] {
        guard let ctx = context, let res = ctx.pointee.resources else { return [] }
        var result: [ResourceEntry] = []

        let count = Int(res.pointee.entry_count)
        for i in 0..<count {
            let e = res.pointee.entries.advanced(by: i).pointee
            let name: String
            if let en = e.entry_name {
                name = String(cString: en)
            } else {
                name = String(format: "0x%08X", e.id)
            }
            let typeName: String
            if let tn = e.type_name {
                typeName = String(cString: tn)
            } else {
                typeName = resourceTypeName(for: e.value_type)
            }
            let value = formatResourceValue(e)

            result.append(ResourceEntry(
                resourceId: e.id,
                name: name,
                type: typeName,
                value: value
            ))
        }

        return result
    }

    private func resourceTypeName(for valueType: UInt8) -> String {
        // Resource value type constants from DxResValueType C enum
        switch valueType {
        case 3: return "string"      // DX_RES_TYPE_STRING
        case 16: return "integer"    // DX_RES_TYPE_INT_DEC
        case 17: return "integer-hex" // DX_RES_TYPE_INT_HEX
        case 18: return "bool"       // DX_RES_TYPE_INT_BOOL
        case 28, 29, 30, 31: return "color" // ARGB8, RGB8, ARGB4, RGB4
        case 5: return "dimen"       // DX_RES_TYPE_DIMEN
        case 4: return "float"       // DX_RES_TYPE_FLOAT
        case 1: return "reference"   // DX_RES_TYPE_REF
        case 6: return "fraction"    // DX_RES_TYPE_FRACTION
        default: return "unknown"
        }
    }

    private func formatResourceValue(_ e: DxResourceEntry) -> String {
        // Resource value type constants from DxResValueType C enum
        switch e.value_type {
        case 3: // DX_RES_TYPE_STRING
            if let s = e.str_val {
                return String(cString: s)
            }
            return "(null)"
        case 16: // DX_RES_TYPE_INT_DEC
            return "\(e.int_val)"
        case 17: // DX_RES_TYPE_INT_HEX
            return String(format: "0x%08X", e.int_val)
        case 18: // DX_RES_TYPE_INT_BOOL
            return e.bool_val ? "true" : "false"
        case 28, 29, 30, 31: // DX_RES_TYPE_INT_COLOR_*
            return String(format: "#%08X", e.color_val)
        case 5: // DX_RES_TYPE_DIMEN
            let unitNames = ["px", "dp", "sp", "pt", "in", "mm"]
            let unit = Int(e.dimen.unit)
            let unitStr = unit < unitNames.count ? unitNames[unit] : "?"
            return String(format: "%.1f%@", e.dimen.value, unitStr)
        case 4: // DX_RES_TYPE_FLOAT
            return String(format: "%.4f", e.float_val)
        case 1: // DX_RES_TYPE_REF
            return String(format: "@0x%08X", e.ref_id)
        default:
            return "(type \(e.value_type))"
        }
    }

    private func formatResConfig(_ cfg: DxResConfig) -> String {
        var parts: [String] = []
        let lang = withUnsafeBytes(of: cfg.language) { buf -> String in
            let bytes = Array(buf.prefix(2))
            if bytes[0] != 0 { return String(bytes: bytes.filter { $0 != 0 }, encoding: .ascii) ?? "" }
            return ""
        }
        if !lang.isEmpty { parts.append(lang) }

        let country = withUnsafeBytes(of: cfg.country) { buf -> String in
            let bytes = Array(buf.prefix(2))
            if bytes[0] != 0 { return "r" + (String(bytes: bytes.filter { $0 != 0 }, encoding: .ascii) ?? "") }
            return ""
        }
        if !country.isEmpty { parts.append(country) }

        if cfg.density != 0 {
            switch cfg.density {
            case 120: parts.append("ldpi")
            case 160: parts.append("mdpi")
            case 240: parts.append("hdpi")
            case 320: parts.append("xhdpi")
            case 480: parts.append("xxhdpi")
            case 640: parts.append("xxxhdpi")
            default: parts.append("\(cfg.density)dpi")
            }
        }

        if cfg.orientation == 1 { parts.append("port") }
        else if cfg.orientation == 2 { parts.append("land") }

        if cfg.night_mode == 1 { parts.append("notnight") }
        else if cfg.night_mode == 2 { parts.append("night") }

        if cfg.sdk_version != 0 { parts.append("v\(cfg.sdk_version)") }

        return parts.joined(separator: "-")
    }

    // MARK: - Diagnostics

    /// Dump the UI tree hierarchy as a formatted string
    func dumpUITree() -> String {
        guard let ctx = context else { return "(no context)" }
        guard let root = ctx.pointee.ui_root else { return "(no UI tree)" }
        guard let cStr = dx_ui_tree_dump(root) else { return "(dump failed)" }
        let result = String(cString: cStr)
        dx_free(cStr)
        return result
    }

    /// Get heap statistics as a formatted string
    func heapStats() -> String {
        guard let ctx = context, let vm = ctx.pointee.vm else { return "(no VM)" }
        guard let cStr = dx_vm_heap_stats(vm) else { return "(stats failed)" }
        let result = String(cString: cStr)
        dx_free(cStr)
        return result
    }

    /// Get the missing features report from the VM
    func missingFeaturesReport() -> String {
        guard let ctx = context, let vm = ctx.pointee.vm else { return "(no VM)" }
        guard let cStr = dx_vm_get_missing_features(vm) else { return "(none)" }
        return String(cString: cStr)
    }

    /// Get last error detail with register snapshot and stack trace
    func lastErrorDetail() -> String {
        guard let ctx = context, let vm = ctx.pointee.vm else { return "(no VM)" }
        guard let cStr = dx_vm_get_last_error_detail(vm) else { return "(no detail)" }
        let result = String(cString: cStr)
        dx_free(cStr)
        return result
    }

    /// Copy all logs as text (for sharing/debugging)
    func copyLogsToClipboard() -> String {
        return logs.map { entry in
            let ts = Self.logDateFormatter.string(from: entry.timestamp)
            return "[\(ts)] [\(entry.level)] \(entry.tag): \(entry.message)"
        }.joined(separator: "\n")
    }

    // MARK: - Telemetry

    /// Enable or disable opt-in telemetry counters in the VM.
    func setTelemetryEnabled(_ enabled: Bool) {
        guard let ctx = context, let vm = ctx.pointee.vm else { return }
        dx_vm_set_telemetry_enabled(vm, enabled)
    }

    /// Read a snapshot of the VM telemetry counters as a Swift dictionary.
    func getTelemetry() -> [String: Any] {
        guard let ctx = context, let vm = ctx.pointee.vm else { return [:] }
        let t = dx_vm_get_telemetry(vm)
        return [
            "totalInstructionsExecuted": t.total_instructions_executed,
            "totalGCCollections":        t.total_gc_collections,
            "totalGCPauseNs":            t.total_gc_pause_ns,
            "totalMethodsInvoked":       t.total_methods_invoked,
            "classesLoaded":             t.classes_loaded,
            "exceptionsThrown":          t.exceptions_thrown,
            "telemetryEnabled":          t.telemetry_enabled,
        ]
    }

    // MARK: - Private

    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private func enqueuLog(level: String, tag: String, message: String) {
        pendingLogs.append((level, tag, message))

        // Throttle: only flush at most once per run loop iteration
        if !logFlushScheduled {
            logFlushScheduled = true
            // Use DispatchQueue.main.async to batch all logs from this cycle
            DispatchQueue.main.async { [weak self] in
                self?.flushPendingLogs()
            }
        }
    }

    private func flushPendingLogs() {
        logFlushScheduled = false
        let batch = pendingLogs
        pendingLogs = []

        for (level, tag, message) in batch {
            addLog(level: level, tag: tag, message: message)
        }
    }

    private func addLog(level: String, tag: String, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, tag: tag, message: message)
        logs.append(entry)
        // Keep last entries capped
        if logs.count > Self.maxLogs {
            logs.removeFirst(logs.count - Self.maxLogs)
        }
    }

    nonisolated private static func nodeFromC(_ n: DxRenderNode) -> RenderNode {
        var children: [RenderNode] = []
        if n.child_count > 0, let childPtr = n.children {
            for i in 0..<Int(n.child_count) {
                children.append(nodeFromC(childPtr.advanced(by: i).pointee))
            }
        }

        // Extract image data if present
        var imgData: Data? = nil
        if let ptr = n.image_data, n.image_data_len > 0 {
            imgData = Data(bytes: ptr, count: Int(n.image_data_len))
        }

        let ca = n.constraints
        let anchors = ConstraintAnchors(
            leftToLeft: ca.left_to_left,
            leftToRight: ca.left_to_right,
            rightToRight: ca.right_to_right,
            rightToLeft: ca.right_to_left,
            topToTop: ca.top_to_top,
            topToBottom: ca.top_to_bottom,
            bottomToBottom: ca.bottom_to_bottom,
            bottomToTop: ca.bottom_to_top,
            horizontalBias: ca.horizontal_bias,
            verticalBias: ca.vertical_bias,
            hChainStyle: ca.h_chain_style,
            vChainStyle: ca.v_chain_style
        )

        // Convert draw commands
        var drawCmds: [DrawCommand] = []
        if n.draw_cmd_count > 0, let cmdPtr = n.draw_commands {
            for i in 0..<Int(n.draw_cmd_count) {
                let c = cmdPtr.advanced(by: i).pointee
                let txt: String? = c.text.map { String(cString: $0) }
                drawCmds.append(DrawCommand(
                    type: c.type,
                    params: c.params,
                    color: c.color,
                    strokeWidth: c.stroke_width,
                    paintStyle: c.paint_style,
                    textSize: c.text_size,
                    text: txt
                ))
            }
        }

        // Extract shape drawable background if present
        let shapeBg: ShapeBackground? = n.shape_bg.has_shape ? ShapeBackground(
            shapeType: n.shape_bg.shape_type,
            solidColor: n.shape_bg.solid_color,
            cornerRadius: n.shape_bg.corner_radius,
            strokeWidth: n.shape_bg.stroke_width,
            strokeColor: n.shape_bg.stroke_color,
            gradientStart: n.shape_bg.gradient_start,
            gradientEnd: n.shape_bg.gradient_end,
            gradientType: n.shape_bg.gradient_type
        ) : nil

        return RenderNode(
            type: n.type,
            viewId: n.view_id,
            text: n.text.map { String(cString: $0) },
            hint: n.hint.map { String(cString: $0) },
            orientation: n.orientation,
            textSize: n.text_size,
            width: n.width,
            height: n.height,
            weight: n.weight,
            gravity: n.gravity,
            padding: (n.padding.0, n.padding.1, n.padding.2, n.padding.3),
            margin: (n.margin.0, n.margin.1, n.margin.2, n.margin.3),
            bgColor: n.bg_color,
            textColor: n.text_color,
            isChecked: n.is_checked,
            inputType: n.input_type,
            scaleType: n.scale_type,
            visibility: n.visibility,
            hasClickListener: n.has_click_listener,
            hasLongClickListener: n.has_long_click_listener,
            hasRefreshListener: n.has_refresh_listener,
            relativeFlags: n.relative_flags,
            relAbove: n.rel_above,
            relBelow: n.rel_below,
            relLeftOf: n.rel_left_of,
            relRightOf: n.rel_right_of,
            constraints: anchors,
            isGuideline: n.is_guideline,
            guidelineOrientation: n.guideline_orientation,
            guidelinePercent: n.guideline_percent,
            guidelineBegin: n.guideline_begin,
            imageData: imgData,
            isNinePatch: n.is_nine_patch,
            ninePatchPadding: (n.nine_patch_padding.0, n.nine_patch_padding.1,
                               n.nine_patch_padding.2, n.nine_patch_padding.3),
            ninePatchStretchX: (n.nine_patch_stretch_x.0, n.nine_patch_stretch_x.1),
            ninePatchStretchY: (n.nine_patch_stretch_y.0, n.nine_patch_stretch_y.1),
            vectorPathData: n.vector_path_data.map { String(cString: $0) },
            vectorFillColor: n.vector_fill_color,
            vectorStrokeColor: n.vector_stroke_color,
            vectorStrokeWidth: n.vector_stroke_width,
            vectorWidth: n.vector_width,
            vectorHeight: n.vector_height,
            shapeBg: shapeBg,
            webURL: n.web_url.map { String(cString: $0) },
            webHTML: n.web_html.map { String(cString: $0) },
            alpha: n.alpha,
            rotation: n.rotation,
            scaleX: n.scale_x,
            scaleY: n.scale_y,
            translationX: n.translation_x,
            translationY: n.translation_y,
            measuredWidth: n.measured_width,
            measuredHeight: n.measured_height,
            focusable: n.focusable,
            focused: n.focused,
            drawCommands: drawCmds,
            children: children
        )
    }

    nonisolated static func convertRenderModel(_ node: UnsafeMutablePointer<DxRenderNode>?) -> RenderNode? {
        guard let node = node else { return nil }
        return nodeFromC(node.pointee)
    }

    nonisolated private static func convertRenderNode(_ node: inout UnsafeMutablePointer<DxRenderNode>) -> RenderNode? {
        return nodeFromC(node.pointee
        )
    }
}
