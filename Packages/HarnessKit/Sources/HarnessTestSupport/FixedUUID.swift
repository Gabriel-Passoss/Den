import Foundation

public func fixedUUID(_ string: String) -> UUID {
    guard let id = UUID(uuidString: string) else {
        preconditionFailure("\(string) is not a UUID")
    }
    return id
}
