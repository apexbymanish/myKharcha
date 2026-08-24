import Foundation
import SwiftData

public enum KharchaContainerFactory {
    public static let appGroupID = "group.com.manish.jebkharcha"

    public static func appGroup(identifier: String = appGroupID) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(KharchaSchema.models),
            configurations: [ModelConfiguration(groupContainer: .identifier(identifier))]
        )
    }

    public static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(KharchaSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    /// Dev fallback when the App Group container is unavailable (e.g. missing entitlement).
    public static func localOnDisk() throws -> ModelContainer {
        try ModelContainer(for: Schema(KharchaSchema.models), configurations: [ModelConfiguration()])
    }
}
