import SwiftUI

struct DEXBrowserView: View {
    @ObservedObject var bridge: RuntimeBridge
    @State private var searchText = ""
    @State private var classes: [DEXClassInfo] = []
    @State private var isLoading = false

    var filteredClasses: [DEXClassInfo] {
        if searchText.isEmpty {
            return classes
        }
        return classes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !bridge.isLoaded {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.dxTextSecondary)
                        Text("No APK Loaded")
                            .font(.dxHeadline)
                            .foregroundStyle(Color.dxText)
                        Text("Load an APK from the Home tab to browse its DEX contents.")
                            .font(.dxCaption)
                            .foregroundStyle(Color.dxTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dxBackground)
                } else if isLoading {
                    ProgressView("Parsing DEX classes...")
                        .foregroundStyle(Color.dxText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.dxBackground)
                } else if classes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.dxTextSecondary)
                        Text("No Classes Found")
                            .font(.dxHeadline)
                            .foregroundStyle(Color.dxText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dxBackground)
                } else {
                    VStack(spacing: 0) {
                        // Summary bar
                        HStack {
                            Label("\(classes.count) classes", systemImage: "cube.fill")
                                .font(.dxCaption)
                                .foregroundStyle(Color.dxSecondary)
                            Spacer()
                            Label("\(bridge.dexMethodCount) methods", systemImage: "function")
                                .font(.dxCaption)
                                .foregroundStyle(Color.dxPrimary)
                            Spacer()
                            Label("\(bridge.dexStringCount) strings", systemImage: "textformat")
                                .font(.dxCaption)
                                .foregroundStyle(Color.dxWarning)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.dxSurface)

                        List(filteredClasses) { cls in
                            NavigationLink(value: cls) {
                                DEXClassRow(classInfo: cls)
                            }
                            .listRowBackground(Color.dxBackground)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Color.dxBackground)
                    }
                    .background(Color.dxBackground)
                    .navigationDestination(for: DEXClassInfo.self) { cls in
                        DEXClassDetailView(bridge: bridge, classInfo: cls)
                    }
                }
            }
            .navigationTitle("DEX Browser")
            .searchable(text: $searchText, prompt: "Search classes...")
            .onAppear {
                if bridge.isLoaded && classes.isEmpty {
                    loadClasses()
                }
            }
            .onChange(of: bridge.isLoaded) {
                if bridge.isLoaded {
                    loadClasses()
                } else {
                    classes = []
                }
            }
        }
    }

    private func loadClasses() {
        isLoading = true
        classes = bridge.getDEXClasses()
        isLoading = false
    }
}

// MARK: - Class Row

struct DEXClassRow: View {
    let classInfo: DEXClassInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(classInfo.displayName)
                .font(.dxCode)
                .foregroundStyle(Color.dxText)
                .lineLimit(1)

            HStack(spacing: 12) {
                Label("\(classInfo.methodCount)", systemImage: "function")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dxPrimary)
                Label("\(classInfo.fieldCount)", systemImage: "list.bullet")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dxSecondary)

                if !classInfo.accessFlagsText.isEmpty {
                    Text(classInfo.accessFlagsText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.dxTextSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Class Detail

struct DEXClassDetailView: View {
    let bridge: RuntimeBridge
    let classInfo: DEXClassInfo
    @State private var detail: DEXClassDetail?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading class data...")
                    .foregroundStyle(Color.dxText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dxBackground)
            } else if let detail = detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Class header
                        VStack(alignment: .leading, spacing: 4) {
                            Text(classInfo.name)
                                .font(.dxCode)
                                .foregroundStyle(Color.dxPrimary)
                            if !classInfo.accessFlagsText.isEmpty {
                                Text(classInfo.accessFlagsText)
                                    .font(.dxCaption)
                                    .foregroundStyle(Color.dxTextSecondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.dxSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // Methods section
                        if !detail.methods.isEmpty {
                            sectionHeader("Methods (\(detail.methods.count))", icon: "function")

                            ForEach(detail.methods) { method in
                                DEXMethodRow(method: method)
                            }
                        }

                        // Fields section
                        if !detail.fields.isEmpty {
                            sectionHeader("Fields (\(detail.fields.count))", icon: "list.bullet")

                            ForEach(detail.fields) { field in
                                DEXFieldRow(field: field)
                            }
                        }

                        if detail.methods.isEmpty && detail.fields.isEmpty {
                            Text("No class data available (abstract/interface with no code)")
                                .font(.dxCaption)
                                .foregroundStyle(Color.dxTextSecondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding()
                }
                .background(Color.dxBackground)
            } else {
                Text("Failed to load class details")
                    .font(.dxBody)
                    .foregroundStyle(Color.dxError)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dxBackground)
            }
        }
        .navigationTitle(classInfo.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            detail = bridge.getDEXClassDetail(index: classInfo.classDefIndex)
            isLoading = false
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.dxHeadline)
            .foregroundStyle(Color.dxText)
            .padding(.top, 8)
    }
}

// MARK: - Method Row

struct DEXMethodRow: View {
    let method: DEXMethodInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(method.name)
                .font(.dxCode)
                .foregroundStyle(Color.dxPrimary)

            Text(method.descriptor)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.dxTextSecondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                if !method.accessFlagsText.isEmpty {
                    Text(method.accessFlagsText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.dxWarning)
                }

                Text("regs: \(method.registerCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.dxTextSecondary)

                Text("code: \(method.codeSize) units")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.dxTextSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Field Row

struct DEXFieldRow: View {
    let field: DEXFieldInfo

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.name)
                    .font(.dxCode)
                    .foregroundStyle(Color.dxSecondary)
                Text(field.type)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dxTextSecondary)
            }
            Spacer()
            if !field.accessFlagsText.isEmpty {
                Text(field.accessFlagsText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.dxWarning)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
