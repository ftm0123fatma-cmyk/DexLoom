import Foundation

/// Minimum release-gating criteria for DexLoom builds.
/// CI and manual verification should check these thresholds before shipping.
struct ReleaseChecklist {
    static let minimumTestPassRate: Double = 0.95  // 95%
    static let requiredSuites = ["FrameworkClassTests", "NetworkingStubTests", "MemorySafetyTests", "BytecodeExecutionSyntheticTests"]
    static let maxAllowedCrashes = 0
    static let requiredBuildConfigs = ["Debug", "Release"]
}
