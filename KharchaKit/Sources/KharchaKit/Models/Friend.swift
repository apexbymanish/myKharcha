import Foundation
import SwiftData

@Model
public final class Friend {
    public var id: UUID
    public var name: String
    public var phone: String?
    public var photoData: Data?
    public var updatedAt: Date

    public init(name: String, phone: String?, photoData: Data?) {
        self.id = UUID()
        self.name = name
        self.phone = phone
        self.photoData = photoData
        self.updatedAt = .now
    }
}
