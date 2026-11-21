import Foundation

/// Sunucuya henüz iletilmemiş silmeleri hatırlar; silinen kayıt yeniden eşitlemede geri gelmez.
struct PendingDeletionStore {
    private let key: String
    private let defaults: UserDefaults

    /// Anahtar biçimi: `pending<Scope>Deletes.<uid>` (ör. pendingWorkoutDeletes.abc).
    init(userID: String, scope: String = "Workout", defaults: UserDefaults = .standard) {
        self.key = "pending\(scope)Deletes.\(userID)"
        self.defaults = defaults
    }

    var ids: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func add(_ id: String) {
        var current = ids
        current.insert(id)
        defaults.set(Array(current), forKey: key)
    }

    func remove(_ id: String) {
        var current = ids
        current.remove(id)
        defaults.set(Array(current), forKey: key)
    }
}
