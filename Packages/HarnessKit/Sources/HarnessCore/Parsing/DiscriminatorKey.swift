struct DiscriminatorKey: CodingKey {
    let stringValue: String
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.init(stringValue) }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

extension DecodingError {
    static func oneDiscriminatorExpected(
        by type: String, reportingAs key: String,
        in container: KeyedDecodingContainer<DiscriminatorKey>
    ) -> DecodingError {
        .dataCorruptedError(
            forKey: DiscriminatorKey(key),
            in: container,
            debugDescription: "\(type) espera exatamente uma chave discriminadora, achou \(container.allKeys.count)"
        )
    }
}
