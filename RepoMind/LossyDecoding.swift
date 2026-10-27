import Foundation

/// An array that keeps the elements it can read and drops the ones it cannot.
///
/// The contracts RepoMind reads (`docs/stats-contract.md`, `docs/store-contract.md`) come from servers
/// the developer writes. One odd element, a `null` where a string was promised or a date in another
/// shape, used to make the whole file undecodable, and the screen then said "not in the format RepoMind
/// reads" about a file that was fine but for one row. Losing the row is the better failure.
nonisolated struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else if (try? container.decode(DiscardedValue.self)) == nil {
                // Could not even step over it: stop here rather than loop on the same element.
                break
            }
        }
        elements = result
    }
}

/// Any JSON value, read and thrown away: how an unkeyed container steps over an element that failed to
/// decode (a failed `decode` does not advance it).
nonisolated struct DiscardedValue: Decodable {
    init(from decoder: Decoder) throws {}
}

nonisolated extension KeyedDecodingContainer {
    /// The array under `key`, element by element. Absent, `null` or not an array at all is empty.
    func decodeLossyArray<Element: Decodable>(_ key: Key) -> [Element] {
        (try? decode(LossyArray<Element>.self, forKey: key))?.elements ?? []
    }
}
