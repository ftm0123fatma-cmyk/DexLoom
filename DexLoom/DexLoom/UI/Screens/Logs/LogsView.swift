import SwiftUI
import UniformTypeIdentifiers

struct LogsView: View {
    @ObservedObject var bridge: RuntimeBridge
    @State private var filterLevel: String = "ALL"
    @State private var searchText = ""
    @State private var selectedTag: String? = nil
    @State private var autoScroll = true
    @State private var showCopiedToast = false
    @State private var showDiagnostics = false
    @State private var diagnosticText: String = ""
    @State private var diagnosticTitle: String = ""
    @State private var showShareSheet = false
    @State private var shareContent: String = ""

    private let levels = ["ALL", "TRACE", "DEBUG", "INFO", "WARN", "ERROR"]

    /// All unique tags present in current logs
    private var availableTags: [String] {
        let tags = Set(bridge.logs.map { $0.tag })
        return tags.sorted()
    }

    var filteredLogs: [LogEntry] {
        bridge.logs.filter { entry in
            let matchesLevel = filterLevel == "ALL" || entry.level == filterLevel
            let matchesSearch = searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText) || entry.tag.localizedCaseInsensitiveContains(searchText)
            let matchesTag = selectedTag == nil || entry.tag == selectedTag
            return matchesLevel && matchesSearch && matchesTag
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.dxCaption)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Level filter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(levels, id: \.self) { level in
                            Button(level) {
                                filterLevel = level
                            }
                            .font(.dxCaption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(filterLevel == level ? Color.dxPrimary : Color.dxSurface)
                            .foregroundStyle(filterLevel == level ? Color.white : Color.dxTextSecondary)
                            .clipShape(Capsule())
                        }

                        Spacer()

                        // Copy logs button
                        Button {
                            let text = bridge.copyLogsToClipboard()
                            UIPasteboard.general.string = text
                            showCopiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopiedToast = false
                            }
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.dxCaption)
                                .foregroundStyle(Color.dxPrimary)
                        }

                        Button("Clear") {
                            bridge.logs.removeAll()
                        }
                        .font(.dxCaption)
                        .foregroundStyle(Color.dxError)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .background(Color.dxSurface)

                // Tag filter bar
                if !availableTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button {
                                selectedTag = nil
                            } label: {
                                Text("All Tags")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(selectedTag == nil ? Color.dxSecondary : Color.dxSurface)
                                    .foregroundStyle(selectedTag == nil ? Color.white : Color.dxTextSecondary)
                                    .clipShape(Capsule())
                            }

                            ForEach(availableTags, id: \.self) { tag in
                                Button {
                                    selectedTag = (selectedTag == tag) ? nil : tag
                                } label: {
                                    Text(tag)
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(selectedTag == tag ? Color.dxSecondary : Color.dxSurface)
                                        .foregroundStyle(selectedTag == tag ? Color.white : Color.dxTextSecondary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                    .background(Color.dxSurface.opacity(0.7))
                }

                // Log list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredLogs) { entry in
                                LogRowView(entry: entry)
                                    .id(entry.id)
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = "[\(entry.level)] \(entry.tag): \(entry.message)"
                                        } label: {
                                            Label("Copy Line", systemImage: "doc.on.doc")
                                        }
                                        Button {
                                            selectedTag = entry.tag
                                        } label: {
                                            Label("Filter by \"\(entry.tag)\"", systemImage: "line.3.horizontal.decrease.circle")
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: bridge.logs.count) {
                        if autoScroll, let last = filteredLogs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color.dxBackground)
            .navigationTitle("Logs (\(filteredLogs.count))")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            autoScroll.toggle()
                        } label: {
                            Label(autoScroll ? "Auto-scroll On" : "Auto-scroll Off",
                                  systemImage: autoScroll ? "checkmark.circle.fill" : "circle")
                        }

                        Divider()

                        Button {
                            let text = bridge.copyLogsToClipboard()
                            UIPasteboard.general.string = text
                            showCopiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopiedToast = false
                            }
                        } label: {
                            Label("Copy All Logs", systemImage: "doc.on.doc")
                        }

                        // Copy errors only
                        Button {
                            let errorLogs = bridge.logs.filter { $0.level == "ERROR" || $0.level == "WARN" }
                            let text = errorLogs.map { entry in
                                "[\(entry.level)] \(entry.tag): \(entry.message)"
                            }.joined(separator: "\n")
                            UIPasteboard.general.string = text.isEmpty ? "(no errors)" : text
                            showCopiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopiedToast = false
                            }
                        } label: {
                            Label("Copy Errors Only", systemImage: "exclamationmark.triangle")
                        }

                        Divider()

                        // Report generation
                        Button {
                            shareContent = generateCrashReport()
                            showShareSheet = true
                        } label: {
                            Label("Share Report", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            let json = exportLogsAsJSON()
                            UIPasteboard.general.string = json
                            showCopiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopiedToast = false
                            }
                        } label: {
                            Label("Export JSON to Clipboard", systemImage: "curlybraces")
                        }

                        Button {
                            let json = exportLogsAsJSON()
                            shareContent = json
                            showShareSheet = true
                        } label: {
                            Label("Share JSON Logs", systemImage: "square.and.arrow.up.on.square")
                        }

                        Divider()

                        // Diagnostics
                        Button {
                            diagnosticTitle = "UI Tree"
                            diagnosticText = bridge.dumpUITree()
                            showDiagnostics = true
                        } label: {
                            Label("UI Tree Inspector", systemImage: "list.bullet.indent")
                        }

                        Button {
                            diagnosticTitle = "Heap Stats"
                            diagnosticText = bridge.heapStats()
                            showDiagnostics = true
                        } label: {
                            Label("Heap Inspector", systemImage: "memorychip")
                        }

                        Button {
                            diagnosticTitle = "Error Detail"
                            diagnosticText = bridge.lastErrorDetail()
                            showDiagnostics = true
                        } label: {
                            Label("Last Error Detail", systemImage: "ladybug")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if showCopiedToast {
                    VStack {
                        Spacer()
                        Text("Copied to clipboard")
                            .font(.dxCaption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: showCopiedToast)
                }
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticSheetView(
                    title: diagnosticTitle,
                    content: diagnosticText,
                    onCopy: {
                        UIPasteboard.general.string = diagnosticText
                        showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedToast = false
                        }
                    }
                )
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [shareContent])
            }
        }
    }

    // MARK: - Crash Report Generation

    private func generateCrashReport() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        var report = "=== DexLoom Crash Report ===\n"
        report += "Date: \(dateFormatter.string(from: Date()))\n"
        report += "Device: \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)\n"
        report += "App: DexLoom\n\n"

        // APK info
        report += "--- APK Info ---\n"
        report += "Package: \(bridge.packageName ?? "(none)")\n"
        report += "Main Activity: \(bridge.activityName ?? "(none)")\n"
        report += "DEX Classes: \(bridge.dexClassCount)\n"
        report += "DEX Methods: \(bridge.dexMethodCount)\n"
        report += "DEX Strings: \(bridge.dexStringCount)\n"
        report += "Loaded: \(bridge.isLoaded)\n"
        report += "Running: \(bridge.isRunning)\n"
        if let err = bridge.errorMessage {
            report += "Error: \(err)\n"
        }

        report += "\n--- Missing Features ---\n"
        report += bridge.missingFeaturesReport()
        report += "\n"

        report += "\n--- Last Error Detail ---\n"
        report += bridge.lastErrorDetail()
        report += "\n"

        report += "\n--- Heap Stats ---\n"
        report += bridge.heapStats()
        report += "\n"

        report += "\n--- Recent Logs (last 50) ---\n"
        let recentLogs = bridge.logs.suffix(50)
        let logFormatter = DateFormatter()
        logFormatter.dateFormat = "HH:mm:ss.SSS"
        for entry in recentLogs {
            let ts = logFormatter.string(from: entry.timestamp)
            report += "[\(ts)] [\(entry.level)] \(entry.tag): \(entry.message)\n"
        }

        report += "\n=== End Report ===\n"
        return report
    }

    // MARK: - JSON Export

    private func exportLogsAsJSON() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let entries: [[String: String]] = bridge.logs.map { log in
            [
                "timestamp": dateFormatter.string(from: log.timestamp),
                "level": log.level,
                "tag": log.tag,
                "message": log.message
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return jsonString
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Diagnostic Sheet

struct DiagnosticSheetView: View {
    let title: String
    let content: String
    let onCopy: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dxText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color.dxBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onCopy()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}

struct LogRowView: View {
    let entry: LogEntry

    private var levelColor: Color {
        switch entry.level {
        case "ERROR": return .dxError
        case "WARN":  return .dxWarning
        case "INFO":  return .dxSecondary
        case "DEBUG": return .dxPrimary
        default:      return .dxTextSecondary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.dxTextSecondary)

            Text(entry.level.prefix(1))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(levelColor)
                .frame(width: 12)

            Text(entry.tag)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.dxPrimary)
                .frame(width: 60, alignment: .leading)
                .lineLimit(1)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.dxText)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }
}
