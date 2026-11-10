import Observation

/// A dictionary observed entry by entry: a view that reads one key redraws when that key's value changes, not
/// whenever any other key's does, as it would reading a plain dictionary on an `@Observable` model.
final class ObservedDictionary<Key: Hashable, Value> {
    @Observable
    final class Slot {
        var value: Value?
    }

    private var slots: [Key: Slot] = [:]

    /// Reading a key with no value yet still observes it, so the reader redraws once the value arrives.
    subscript(key: Key) -> Value? {
        get { slot(key).value }
        set { slot(key).value = newValue }
    }

    /// The keys that hold a value.
    var keys: [Key] { slots.compactMap { $0.value.value == nil ? nil : $0.key } }

    private func slot(_ key: Key) -> Slot {
        if let slot = slots[key] { return slot }
        let slot = Slot()
        slots[key] = slot
        return slot
    }
}
