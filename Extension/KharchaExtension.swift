import AppIntents
import KharchaKit

@main
struct KharchaIntentsExtension: AppIntentsExtension {}

/// Makes the shared package's intents visible to this extension's metadata.
struct KharchaExtensionPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [KharchaKitPackage.self] }
}
