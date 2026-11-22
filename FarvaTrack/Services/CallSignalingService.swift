import Foundation
import FirebaseFirestore

/// Sesli arama sinyalleşmesi (8H): `chats/{chatId}/calls/{callId}` + `candidates`.
/// Testlerde sahte uygulamayla değiştirilir.
protocol CallSignaling: AnyObject {
    func createCall(_ call: CallDocument) async throws
    /// Teklif yeniden yazılır (ICE yeniden başlatma): `offerVersion` artar.
    func updateOffer(_ offer: SessionDescription, version: Int, chatID: String, callID: String) async throws
    func answer(_ answer: SessionDescription, version: Int, chatID: String, callID: String, at: Date) async throws
    func setStatus(_ status: CallSignalStatus, chatID: String, callID: String, by userID: String, at: Date) async throws
    func addCandidate(_ candidate: CallCandidate, chatID: String, callID: String) async throws

    func observeCall(chatID: String, callID: String,
                     onChange: @escaping @MainActor (CallDocument?) -> Void) -> ChatSubscription
    /// Karşı tarafın ICE adayları (yalnızca yeniler).
    func observeCandidates(chatID: String, callID: String, excluding userID: String,
                           onChange: @escaping @MainActor ([CallCandidate]) -> Void) -> ChatSubscription
    /// Bu kullanıcıyı arayan, hâlâ çalan aramalar.
    func observeIncoming(chatID: String, userID: String,
                         onChange: @escaping @MainActor ([CallDocument]) -> Void) -> ChatSubscription
    func fetchCall(chatID: String, callID: String) async throws -> CallDocument?
}

enum CallField {
    static let collection = "calls"
    static let candidates = "candidates"
    static let callerId = "callerId"
    static let calleeId = "calleeId"
    static let status = "status"
    static let offer = "offer"
    static let answer = "answer"
    static let offerVersion = "offerVersion"
    static let answerVersion = "answerVersion"
    static let createdAt = "createdAt"
    static let answeredAt = "answeredAt"
    static let endedAt = "endedAt"
    static let endedBy = "endedBy"
}

enum CallFirestoreMapper {
    static func description(_ value: Any?) -> SessionDescription? {
        guard let map = value as? [String: Any], let sdp = map["sdp"] as? String,
              let raw = map["type"] as? String, let kind = SessionDescription.Kind(rawValue: raw) else { return nil }
        return SessionDescription(kind: kind, sdp: sdp)
    }

    static func encode(_ description: SessionDescription) -> [String: Any] {
        ["type": description.kind.rawValue, "sdp": description.sdp]
    }

    private static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        return value as? Date
    }

    static func call(id: String, chatID: String, data: [String: Any]) -> CallDocument? {
        guard let caller = data[CallField.callerId] as? String, let callee = data[CallField.calleeId] as? String,
              let raw = data[CallField.status] as? String, let status = CallSignalStatus(rawValue: raw) else { return nil }
        return CallDocument(
            id: id, chatID: chatID, callerID: caller, calleeID: callee, status: status,
            offer: description(data[CallField.offer]), answer: description(data[CallField.answer]),
            offerVersion: (data[CallField.offerVersion] as? NSNumber)?.intValue ?? 1,
            answerVersion: (data[CallField.answerVersion] as? NSNumber)?.intValue ?? 0,
            createdAt: date(data[CallField.createdAt]) ?? .now,
            answeredAt: date(data[CallField.answeredAt]), endedAt: date(data[CallField.endedAt]),
            endedBy: data[CallField.endedBy] as? String
        )
    }

    static func candidate(id: String, data: [String: Any]) -> CallCandidate? {
        guard let from = data["from"] as? String, let candidate = data["candidate"] as? String else { return nil }
        return CallCandidate(id: id, from: from, candidate: candidate, sdpMid: data["sdpMid"] as? String,
                             sdpMLineIndex: (data["sdpMLineIndex"] as? NSNumber)?.int32Value ?? 0,
                             offerVersion: (data["offerVersion"] as? NSNumber)?.intValue ?? 1)
    }
}

final class CallSignalingService: CallSignaling {
    private var db: Firestore {
        get throws {
            guard FirebaseBootstrap.isConfigured else { throw AppError.firebaseNotConfigured }
            return Firestore.firestore()
        }
    }

    private func calls(_ chatID: String) throws -> CollectionReference {
        try db.collection(Constants.Collection.chats).document(chatID).collection(CallField.collection)
    }

    private func perform(_ work: () async throws -> Void) async throws {
        do { try await work() } catch { throw AppError.map(error) }
    }

    func createCall(_ call: CallDocument) async throws {
        try await perform {
            var fields: [String: Any] = [
                CallField.callerId: call.callerID,
                CallField.calleeId: call.calleeID,
                CallField.status: call.status.rawValue,
                CallField.offerVersion: call.offerVersion,
                CallField.answerVersion: call.answerVersion,
                CallField.createdAt: FieldValue.serverTimestamp()
            ]
            if let offer = call.offer { fields[CallField.offer] = CallFirestoreMapper.encode(offer) }
            try await calls(call.chatID).document(call.id).setData(fields)
        }
    }

    func updateOffer(_ offer: SessionDescription, version: Int, chatID: String, callID: String) async throws {
        try await perform {
            try await calls(chatID).document(callID).updateData([
                CallField.offer: CallFirestoreMapper.encode(offer), CallField.offerVersion: version
            ])
        }
    }

    func answer(_ answer: SessionDescription, version: Int, chatID: String, callID: String, at date: Date) async throws {
        try await perform {
            var fields: [String: Any] = [CallField.answer: CallFirestoreMapper.encode(answer), CallField.answerVersion: version]
            if version <= 1 {
                fields[CallField.status] = CallSignalStatus.accepted.rawValue
                fields[CallField.answeredAt] = Timestamp(date: date)
            }
            try await calls(chatID).document(callID).updateData(fields)
        }
    }

    func setStatus(_ status: CallSignalStatus, chatID: String, callID: String, by userID: String, at date: Date) async throws {
        try await perform {
            var fields: [String: Any] = [CallField.status: status.rawValue]
            if status.isFinal {
                fields[CallField.endedAt] = Timestamp(date: date)
                fields[CallField.endedBy] = userID
            }
            try await calls(chatID).document(callID).updateData(fields)
        }
    }

    func addCandidate(_ candidate: CallCandidate, chatID: String, callID: String) async throws {
        try await perform {
            var fields: [String: Any] = [
                "from": candidate.from, "candidate": candidate.candidate, "sdpMLineIndex": candidate.sdpMLineIndex,
                "offerVersion": candidate.offerVersion, "createdAt": FieldValue.serverTimestamp()
            ]
            if let mid = candidate.sdpMid { fields["sdpMid"] = mid }
            try await calls(chatID).document(callID).collection(CallField.candidates).document(candidate.id).setData(fields)
        }
    }

    func observeCall(chatID: String, callID: String, onChange: @escaping @MainActor (CallDocument?) -> Void) -> ChatSubscription {
        guard let reference = try? calls(chatID).document(callID) else { return .none }
        let registration = reference.addSnapshotListener { snapshot, _ in
            let call = snapshot.flatMap { doc in doc.data().flatMap { CallFirestoreMapper.call(id: doc.documentID, chatID: chatID, data: $0) } }
            Task { @MainActor in onChange(call) }
        }
        return ChatSubscription { registration.remove() }
    }

    func observeCandidates(chatID: String, callID: String, excluding userID: String,
                           onChange: @escaping @MainActor ([CallCandidate]) -> Void) -> ChatSubscription {
        guard let collection = try? calls(chatID).document(callID).collection(CallField.candidates) else { return .none }
        let registration = collection.addSnapshotListener { snapshot, _ in
            guard let snapshot else { return }
            let added = snapshot.documentChanges
                .filter { $0.type == .added }
                .compactMap { CallFirestoreMapper.candidate(id: $0.document.documentID, data: $0.document.data()) }
                .filter { $0.from != userID }
            guard !added.isEmpty else { return }
            Task { @MainActor in onChange(added) }
        }
        return ChatSubscription { registration.remove() }
    }

    func observeIncoming(chatID: String, userID: String, onChange: @escaping @MainActor ([CallDocument]) -> Void) -> ChatSubscription {
        guard let query = try? calls(chatID)
            .whereField(CallField.calleeId, isEqualTo: userID)
            .whereField(CallField.status, isEqualTo: CallSignalStatus.ringing.rawValue) else { return .none }
        let registration = query.addSnapshotListener { snapshot, _ in
            let calls = snapshot?.documents.compactMap { CallFirestoreMapper.call(id: $0.documentID, chatID: chatID, data: $0.data()) } ?? []
            Task { @MainActor in onChange(calls) }
        }
        return ChatSubscription { registration.remove() }
    }

    func fetchCall(chatID: String, callID: String) async throws -> CallDocument? {
        do {
            let doc = try await calls(chatID).document(callID).getDocument()
            return doc.data().flatMap { CallFirestoreMapper.call(id: doc.documentID, chatID: chatID, data: $0) }
        } catch {
            throw AppError.map(error)
        }
    }
}
