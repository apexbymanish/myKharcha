import Foundation
import SwiftData

public enum KharchaContainerFactory {
    public static let appGroupID = "group.com.manish.kharcha"

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
}
