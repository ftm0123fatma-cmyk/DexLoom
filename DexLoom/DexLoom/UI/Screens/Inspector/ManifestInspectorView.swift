import SwiftUI

struct ManifestInspectorView: View {
    @ObservedObject var bridge: RuntimeBridge
    @State private var manifest: ManifestInfo?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if !bridge.isLoaded {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.plaintext")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.dxTextSecondary)
                        Text("No APK Loaded")
                            .font(.dxHeadline)
                            .foregroundStyle(Color.dxText)
                        Text("Load an APK from the Home tab to inspect its manifest.")
                            .font(.dxCaption)
                            .foregroundStyle(Color.dxTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dxBackground)
                } else if isLoading {
                    ProgressView("Parsing manifest...")
                        .foregroundStyle(Color.dxText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.dxBackground)
                } else if let manifest = manifest {
                    manifestContent(manifest)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.dxWarning)
                        Text("Manifest Not Available")
                            .font(.dxHeadline)
                            .foregroundStyle(Color.dxText)
                        Text("Could not parse AndroidManifest.xml from the APK.")
                            .font(.dxCaption)
                            .foregroundStyle(Color.dxTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dxBackground)
                }
            }
            .navigationTitle("Manifest")
            .onAppear {
                if bridge.isLoaded && manifest == nil {
                    loadManifest()
                }
            }
            .onChange(of: bridge.isLoaded) {
                if bridge.isLoaded {
                    loadManifest()
                } else {
                    manifest = nil
                }
            }
        }
    }

    private func loadManifest() {
        isLoading = true
        manifest = bridge.getManifestInfo()
        isLoading = false
    }

    @ViewBuilder
    private func manifestContent(_ info: ManifestInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Package Info
                manifestSection("Package Info", icon: "shippingbox.fill") {
                    manifestField("Package", info.packageName)
                    manifestField("App Label", info.appLabel)
                    manifestField("Min SDK", info.minSdk > 0 ? "\(info.minSdk)" : "not set")
                    manifestField("Target SDK", info.targetSdk > 0 ? "\(info.targetSdk)" : "not set")
                    manifestField("Theme", info.appTheme)
                }

                // Activities
                if !info.activities.isEmpty {
                    manifestSection("Activities (\(info.activities.count))", icon: "rectangle.stack.fill") {
                        ForEach(info.activities) { component in
                            ManifestComponentRow(component: component, isMain: component.name == info.mainActivity)
                        }
                    }
                }

                // Services
                if !info.services.isEmpty {
                    manifestSection("Services (\(info.services.count))", icon: "gearshape.2.fill") {
                        ForEach(info.services) { component in
                            ManifestComponentRow(component: component)
                        }
                    }
                }

                // Receivers
                if !info.receivers.isEmpty {
                    manifestSection("Receivers (\(info.receivers.count))", icon: "antenna.radiowaves.left.and.right") {
                        ForEach(info.receivers) { component in
                            ManifestComponentRow(component: component)
                        }
                    }
                }

                // Providers
                if !info.providers.isEmpty {
                    manifestSection("Providers (\(info.providers.count))", icon: "externaldrive.fill") {
                        ForEach(info.providers) { component in
                            ManifestComponentRow(component: component)
                        }
                    }
                }

                // Permissions
                if !info.permissions.isEmpty {
                    manifestSection("Permissions (\(info.permissions.count))", icon: "lock.shield.fill") {
                        ForEach(info.permissions, id: \.self) { perm in
                            Text(perm)
                                .font(.dxCode)
                                .foregroundStyle(Color.dxText)
                                .padding(.vertical, 2)
                        }
                    }
                }

                // Features
                if !info.features.isEmpty {
                    manifestSection("Features (\(info.features.count))", icon: "star.fill") {
                        ForEach(info.features, id: \.name) { feature in
                            HStack {
                                Text(feature.name)
                                    .font(.dxCode)
                                    .foregroundStyle(Color.dxText)
                                Spacer()
                                Text(feature.required ? "required" : "optional")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(feature.required ? Color.dxWarning : Color.dxTextSecondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.dxBackground)
    }

    private func manifestSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.dxHeadline)
                .foregroundStyle(Color.dxText)

            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dxSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func manifestField(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.dxCaption)
                .foregroundStyle(Color.dxTextSecondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.dxCode)
                .foregroundStyle(Color.dxText)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Component Row

struct ManifestComponentRow: View {
    let component: ManifestComponentInfo
    var isMain: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(component.name)
                    .font(.dxCode)
                    .foregroundStyle(isMain ? Color.dxSecondary : Color.dxText)
                    .lineLimit(2)

                if isMain {
                    Text("LAUNCHER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.dxSecondary.opacity(0.2))
                        .foregroundStyle(Color.dxSecondary)
                        .clipShape(Capsule())
                }

                if component.exported {
                    Text("exported")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.dxWarning)
                }
            }

            // Intent filters
            ForEach(component.intentFilters) { filter in
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filter.actions, id: \.self) { action in
                        HStack(spacing: 4) {
                            Text("action:")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.dxTextSecondary)
                            Text(action)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.dxPrimary)
                        }
                    }
                    ForEach(filter.categories, id: \.self) { category in
                        HStack(spacing: 4) {
                            Text("category:")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.dxTextSecondary)
                            Text(category)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.dxPrimary)
                        }
                    }
                }
                .padding(.leading, 12)
            }
        }
        .padding(.vertical, 4)
    }
}
