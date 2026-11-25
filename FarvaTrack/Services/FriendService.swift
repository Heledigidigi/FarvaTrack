import Foundation
import FirebaseFirestore

/// Kullanıcı adı, arkadaş arama ve arkadaşlık istekleri.
///
/// - `usernames/{ad}`: `{uid, displayName, photoURL?}`. Ad benzersizdir (belge kimliği); herkes okuyabilir,
///   yalnızca sahibi yazar/siler.
/// - `friendRequests/{gönderen}_{alan}`: `{from, to, fromName, fromUsername, fromPhoto?, toName, toUsername, createdAt}`.
///   Alan kişi kabul edince aynı toplu yazımda `chats/{oda}` açılır (kural isteği okuyarak doğrular) ve istek silinir.
protocol FriendSyncing: AnyObject {
    /// Kullanıcının kendi adı (henüz seçmediyse `nil`).
    func username(of userID: String) async throws -> String?
    /// Adı alır; başkasındaysa `invalidInput`. Eski ad (varsa) silinir.
    func claimUsername(_ name: String, userID: String, displayName: String, photoURL: String?, previous: String?) async throws
    /// Adın başı eşleşen kişiler (en çok 20).
    func search(prefix: String) async throws -> [FriendProfile]
    func sendRequest(from: FriendProfile, to: FriendProfile, now: Date) async throws
    /// Bana gelen ve benim gönderdiğim bekleyen istekler.
    func observeRequests(
        userID: String,
        onChange: @escaping @MainActor (_ incoming: [FriendRequest], _ outgoing: [FriendRequest]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> ChatSubscription
    /// Kabul: oda açılır, istek silinir. Oda zaten varsa yalnızca istek silinir.
    func accept(_ request: FriendRequest, roomExists: Bool, now: Date) async throws -> ChatRoomDTO
    /// Reddet ya da geri çek.
    func remove(_ request: FriendRequest) async throws
    /// Kendime not sohbeti (davet kodu gerekmez).
    func createPersonalRoom(userID: String, userName: String, now: Date) async throws -> ChatRoomDTO
    /// Hesap silinirken: kullanıcı adı ve istekler.
    func purge(userID: String) async throws
}

enum FriendField {
    static let usernames = "usernames"
    static let requests = "friendRequests"
    static let uid = "uid"
    static let displayName = "displayName"
    static let photoURL = "photoURL"
    static let from = "from"
    static let to = "to"
    static let fromName = "fromName"
    static let fromUsername = "fromUsername"
    static let fromPhoto = "fromPhoto"
    static let toName = "toName"
    static let toUsername = "toUsername"
    static let createdAt = "createdAt"
    /// Odada hangi istekle açıldığı (kural doğrulaması için).
    static let friendRequest = "friendRequest"
}

enum FriendMapper {
    static func request(_ data: [String: Any]) -> FriendRequest? {
        guard let from = data[FriendField.from] as? String, let to = data[FriendField.to] as? String else { return nil }
        let created = (data[FriendField.createdAt] as? Timestamp)?.dateValue() ?? .distantPast
        return FriendRequest(
            from: FriendProfile(userID: from, username: data[FriendField.fromUsername] as? String ?? "",
                                displayName: data[FriendField.fromName] as? String ?? "", photoURL: data[FriendField.fromPhoto] as? String),
            to: FriendProfile(userID: to, username: data[FriendField.toUsername] as? String ?? "",
                              displayName: data[FriendField.toName] as? String ?? ""),
            createdAt: created
        )
    }
}

final class FriendService: FriendSyncing {
    private var db: Firestore {
        get throws {
            guard FirebaseBootstrap.isConfigured else { throw AppError.firebaseNotConfigured }
            return Firestore.firestore()
        }
    }

    private func usernames() throws -> CollectionReference { try db.collection(FriendField.usernames) }
    private func requests() throws -> CollectionReference { try db.collection(FriendField.requests) }

    func username(of userID: String) async throws -> String? {
        do {
            let snapshot = try await usernames().whereField(FriendField.uid, isEqualTo: userID).limit(to: 1).getDocuments()
            return snapshot.documents.first?.documentID
        } catch {
            throw AppError.map(error)
        }
    }

    func claimUsername(_ name: String, userID: String, displayName: String, photoURL: String?, previous: String?) async throws {
        guard ChatUsername.isValid(name) else { throw AppError.invalidInput(ChatUsername.problem(name) ?? "Geçersiz kullanıcı adı.") }
        do {
            let reference = try usernames().document(name)
            let snapshot = try await reference.getDocument(source: .server)
            if snapshot.exists, (snapshot.data()?[FriendField.uid] as? String) != userID {
                throw AppError.invalidInput("@\(name) başka birine ait. Başka bir ad dene.")
            }
            var data: [String: Any] = [FriendField.uid: userID, FriendField.displayName: displayName]
            if let photoURL { data[FriendField.photoURL] = photoURL }
            let batch = try db.batch()
            batch.setData(data, forDocument: reference)
            if let previous, previous != name { batch.deleteDocument(try usernames().document(previous)) }
            try await batch.commit()
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.map(error)
        }
    }

    func search(prefix: String) async throws -> [FriendProfile] {
        let query = ChatUsername.normalize(prefix)
        guard !query.isEmpty else { return [] }
        do {
            let snapshot = try await usernames()
                .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: query)
                .whereField(FieldPath.documentID(), isLessThan: query + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments()
            return snapshot.documents.compactMap { document in
                guard let uid = document.data()[FriendField.uid] as? String else { return nil }
                return FriendProfile(userID: uid, username: document.documentID,
                                     displayName: document.data()[FriendField.displayName] as? String ?? document.documentID,
                                     photoURL: document.data()[FriendField.photoURL] as? String)
            }
        } catch {
            throw AppError.map(error)
        }
    }

    func sendRequest(from: FriendProfile, to: FriendProfile, now: Date) async throws {
        do {
            var data: [String: Any] = [
                FriendField.from: from.userID, FriendField.to: to.userID,
                FriendField.fromName: from.displayName, FriendField.fromUsername: from.username,
                FriendField.toName: to.displayName, FriendField.toUsername: to.username,
                FriendField.createdAt: Timestamp(date: now)
            ]
            if let photo = from.photoURL { data[FriendField.fromPhoto] = photo }
            try await requests().document(FriendRequest.id(from: from.userID, to: to.userID)).setData(data)
        } catch {
            throw AppError.map(error)
        }
    }

    func observeRequests(
        userID: String,
        onChange: @escaping @MainActor ([FriendRequest], [FriendRequest]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> ChatSubscription {
        guard let collection = try? requests() else {
            Task { @MainActor in onError(.firebaseNotConfigured) }
            return .none
        }
        // İki dinleyicinin son sonuçları birlikte bildirilir.
        final class State: @unchecked Sendable {
            var incoming: [FriendRequest] = []
            var outgoing: [FriendRequest] = []
        }
        let state = State()
        func listen(_ field: String, store: @escaping ([FriendRequest]) -> Void) -> ListenerRegistration {
            collection.whereField(field, isEqualTo: userID).addSnapshotListener { snapshot, error in
                if let error {
                    Task { @MainActor in onError(AppError.map(error)) }
                    return
                }
                let items = (snapshot?.documents ?? []).compactMap { FriendMapper.request($0.data()) }
                    .sorted { $0.createdAt > $1.createdAt }
                Task { @MainActor in
                    store(items)
                    onChange(state.incoming, state.outgoing)
                }
            }
        }
        let incoming = listen(FriendField.to) { state.incoming = $0 }
        let outgoing = listen(FriendField.from) { state.outgoing = $0 }
        return ChatSubscription {
            incoming.remove()
            outgoing.remove()
        }
    }

    func accept(_ request: FriendRequest, roomExists: Bool, now: Date) async throws -> ChatRoomDTO {
        let members = ChatID.sortedMembers(request.from.userID, request.to.userID)
        let chatID = ChatID.make(request.from.userID, request.to.userID)
        let names = [request.from.userID: request.from.displayName, request.to.userID: request.to.displayName]
        let room = ChatRoomDTO(id: chatID, members: members, names: names, createdAt: now)
        do {
            let batch = try db.batch()
            if !roomExists {
                batch.setData([
                    ChatField.members: members,
                    ChatField.names: names,
                    ChatField.createdAt: Timestamp(date: now),
                    FriendField.friendRequest: request.id,
                    ChatField.typing: [String: Any]()
                ], forDocument: try db.collection(Constants.Collection.chats).document(chatID))
            }
            batch.deleteDocument(try requests().document(request.id))
            try await batch.commit()
            return room
        } catch {
            throw AppError.map(error)
        }
    }

    func remove(_ request: FriendRequest) async throws {
        do {
            try await requests().document(request.id).delete()
        } catch {
            throw AppError.map(error)
        }
    }

    func createPersonalRoom(userID: String, userName: String, now: Date) async throws -> ChatRoomDTO {
        let chatID = ChatID.make(userID, userID)
        let room = ChatRoomDTO(id: chatID, members: [userID, userID], names: [userID: userName], createdAt: now)
        do {
            try await db.collection(Constants.Collection.chats).document(chatID).setData([
                ChatField.members: [userID, userID],
                ChatField.names: [userID: userName],
                ChatField.createdAt: Timestamp(date: now),
                ChatField.typing: [String: Any]()
            ])
            return room
        } catch {
            throw AppError.map(error)
        }
    }

    func purge(userID: String) async throws {
        do {
            for document in try await usernames().whereField(FriendField.uid, isEqualTo: userID).getDocuments().documents {
                try await document.reference.delete()
            }
            for field in [FriendField.from, FriendField.to] {
                for document in try await requests().whereField(field, isEqualTo: userID).getDocuments().documents {
                    try await document.reference.delete()
                }
            }
        } catch {
            throw AppError.map(error)
        }
    }
}
