struct içine ekleyin:

    /// Tek bir belgeyi okur (yoksa `nil`).
    func fetchDocument<T: Decodable>(_ type: T.Type, id: String, userID: String) async throws -> T? {
        do {
            let snapshot = try await collection(for: userID).document(id).getDocument()
            guard snapshot.exists else { return nil }
            return try snapshot.data(as: T.self)
        } catch {
            throw AppError.map(error)
        }
    }