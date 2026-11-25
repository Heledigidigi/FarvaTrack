import Foundation

// MARK: - Sohbet listesinde açılacak yer

/// Sohbet sekmesindeki bir konuşma: kendime not ya da bir arkadaşla oda.
enum ChatDestination: Hashable {
    case personal
    case room(String)
}

// MARK: - Kullanıcı adı

/// `usernames/{ad}` belgesinin anahtarı: 3–20 karakter, küçük harf, rakam, nokta ve alt çizgi.
/// Türkçe harfler yazılabilir ama İngilizce karşılığına çevrilir (ö → o), böylece arama tutarlı olur.
enum ChatUsername {
    static let minLength = 3
    static let maxLength = 20

    /// "@Özgür.Bozkurt " → "ozgur.bozkurt"
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("@") { text.removeFirst() }
        let map: [Character: Character] = ["ç": "c", "ğ": "g", "ı": "i", "İ": "i", "ö": "o", "ş": "s", "ü": "u",
                                           "Ç": "c", "Ğ": "g", "Ö": "o", "Ş": "s", "Ü": "u", " ": "_"]
        let folded = String(text.map { map[$0] ?? $0 }).lowercased()
        return String(folded.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") })
    }

    /// `nil`: geçerli. Aksi halde kullanıcıya gösterilecek açıklama.
    static func problem(_ name: String) -> String? {
        if name.count < minLength { return "Kullanıcı adı en az \(minLength) karakter olmalı." }
        if name.count > maxLength { return "Kullanıcı adı en fazla \(maxLength) karakter olabilir." }
        if name.hasPrefix(".") || name.hasSuffix(".") { return "Kullanıcı adı nokta ile başlayıp bitemez." }
        if name.contains("..") { return "Art arda iki nokta kullanılamaz." }
        guard name.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "." || $0 == "_") }) else {
            return "Yalnızca harf, rakam, nokta ve alt çizgi kullanılabilir."
        }
        return nil
    }

    static func isValid(_ name: String) -> Bool { problem(name) == nil }

    /// Ad soyaddan öneri: "Özgür Bozkurt" → "ozgur.bozkurt".
    static func suggestion(from displayName: String) -> String {
        let parts = displayName.split(separator: " ").map { normalize(String($0)).replacingOccurrences(of: "_", with: "") }
        let joined = parts.filter { !$0.isEmpty }.joined(separator: ".")
        return String(joined.prefix(maxLength))
    }
}

// MARK: - Arkadaş

/// Arama sonucu / istek tarafı.
struct FriendProfile: Equatable, Hashable, Identifiable {
    var id: String { userID }
    let userID: String
    let username: String
    let displayName: String
    var photoURL: String?
}

/// `friendRequests/{gönderen}_{alan}`: alan kişi kabul edince oda açılır ve istek silinir.
struct FriendRequest: Equatable, Hashable, Identifiable {
    let from: FriendProfile
    let to: FriendProfile
    let createdAt: Date

    var id: String { Self.id(from: from.userID, to: to.userID) }

    static func id(from: String, to: String) -> String { "\(from)_\(to)" }

    /// İsteğin diğer tarafı.
    func other(than userID: String) -> FriendProfile { from.userID == userID ? to : from }
}

/// Bir kişinin bana göre durumu (arama sonucunda gösterilir).
enum FriendRelation: Equatable {
    case me, friend, requestSent, requestReceived, none

    static func of(_ userID: String, me: String, friends: Set<String>, incoming: [FriendRequest], outgoing: [FriendRequest]) -> FriendRelation {
        if userID == me { return .me }
        if friends.contains(userID) { return .friend }
        if outgoing.contains(where: { $0.to.userID == userID }) { return .requestSent }
        if incoming.contains(where: { $0.from.userID == userID }) { return .requestReceived }
        return .none
    }
}

// MARK: - Oda listesi önbelleği

/// Arkadaş odaları: uygulama çevrimdışı açılınca da liste görünsün diye.
struct ChatRoomListCache {
    let defaults: UserDefaults

    private func key(_ userID: String) -> String { "chatRooms.\(userID)" }

    func load(userID: String) -> [ChatRoomDTO] {
        guard let data = defaults.data(forKey: key(userID)) else { return [] }
        return (try? JSONDecoder().decode([ChatRoomDTO].self, from: data)) ?? []
    }

    func save(_ rooms: [ChatRoomDTO], userID: String) {
        let stored = rooms.map { room -> ChatRoomDTO in
            var copy = room
            copy.typing = [:]
            return copy
        }
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: key(userID)) }
    }

    func clear(userID: String) {
        defaults.removeObject(forKey: key(userID))
    }
}
