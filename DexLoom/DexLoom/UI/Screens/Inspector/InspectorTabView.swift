import SwiftUI

struct InspectorTabView: View {
    @ObservedObject var bridge: RuntimeBridge
    @State private var selectedInspector: InspectorType = .dexBrowser

    enum InspectorType: String, CaseIterable {
        case dexBrowser = "DEX Browser"
        case manifest = "Manifest"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker
            Picker("Inspector", selection: $selectedInspector) {
                ForEach(InspectorType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.dxBackground)

            // Content
            switch selectedInspector {
            case .dexBrowser:
                DEXBrowserView(bridge: bridge)
            case .manifest:
                ManifestInspectorView(bridge: bridge)
            }
        }
    }
}
