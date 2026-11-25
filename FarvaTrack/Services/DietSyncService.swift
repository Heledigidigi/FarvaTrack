import Foundation
import FirebaseFirestore

/// Diyet programları Firestore'da kullanıcının altında değil, `dietPrograms/{id}` altında durur:
/// programı inceleyen kişi (`viewerIDs`) de okuyabilsin diye. Kurallar `firebase/firestore.rules`.
protocol DietSyncing: AnyObject {
    func uploadProgram(_ program: DietProgram) async throws
    func deleteProgram(id: String) async throws
    func fetchMyPrograms(userID: String) async throws -> [DietProgram]
    func fetchSharedPrograms(viewerID: String) async throws -> [DietProgram]
    func fetchProgram(id: String) async throws -> DietProgram?

    func uploadLog(_ log: DietMealLog) async throws
    func deleteLog(id: String, programID: String) async throws
    func fetchLogs(programID: String) async throws -> [DietMealLog]

    func uploadNote(_ note: DietDayNote) async throws
    func fetchNotes(programID: String) async throws -> [DietDayNote]

    func addComment(_ comment: DietComment) async throws
    func deleteComment(id: String, programID: String) async throws
    func fetchComments(programID: String) async throws -> [DietComment]

    func createSuggestion(_ suggestion: DietSuggestion) async throws
    func fetchSuggestions(programID: String) async throws -> [DietSuggestion]
    func decideSuggestion(id: String, programID: String, status: DietSuggestionStatus, at: Date) async throws

    func createOffer(_ offer: DietOffer) async throws
    func fetchOffer(id: String) async throws -> DietOffer?
    func decideOffer(id: String, status: DietOfferStatus, programID: String?, at: Date) async throws

    /// Hesap silinirken: kendi programlarım (alt koleksiyonlarıyla), tekliflerim ve başkalarının programındaki yorumlarım.
    func purge(userID: String) async throws
}

enum DietCollection {
    static let programs = "dietPrograms"
    static let logs = "logs"
    static let notes = "notes"
    static let comments = "comments"
    static let suggestions = "suggestions"
    static let offers = "dietOffers"
}

final class DietSyncService: DietSyncing {
    private var db: Firestore {
        get throws {
            guard FirebaseBootstrap.isConfigured else { throw AppError.firebaseNotConfigured }
            return Firestore.firestore()
        }
    }

    private func programs() throws -> CollectionReference { try db.collection(DietCollection.programs) }
    private func sub(_ programID: String, _ name: String) throws -> CollectionReference {
        try programs().document(programID).collection(name)
    }

    private func write<T: Encodable>(_ value: T, to reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try reference.setData(from: value, merge: false) { error in
                    if let error { continuation.resume(throwing: AppError.map(error)) } else { continuation.resume() }
                }
            } catch {
                continuation.resume(throwing: AppError.map(error))
            }
        }
    }

    private func decode<T: Decodable>(_ snapshot: QuerySnapshot, as type: T.Type) -> [T] {
        snapshot.documents.compactMap { try? $0.data(as: T.self) }
    }

    // MARK: Program

    func uploadProgram(_ program: DietProgram) async throws {
        try await write(program, to: programs().document(program.id))
    }

    func deleteProgram(id: String) async throws {
        do {
            for name in [DietCollection.logs, DietCollection.notes, DietCollection.comments, DietCollection.suggestions] {
                try await deleteAll(in: sub(id, name))
            }
            try await programs().document(id).delete()
        } catch {
            throw AppError.map(error)
        }
    }

    func fetchMyPrograms(userID: String) async throws -> [DietProgram] {
        do {
            return decode(try await programs().whereField("ownerID", isEqualTo: userID).getDocuments(), as: DietProgram.self)
        } catch { throw AppError.map(error) }
    }

    func fetchSharedPrograms(viewerID: String) async throws -> [DietProgram] {
        do {
            return decode(try await programs().whereField("viewerIDs", arrayContains: viewerID).getDocuments(), as: DietProgram.self)
        } catch { throw AppError.map(error) }
    }

    func fetchProgram(id: String) async throws -> DietProgram? {
        do {
            let snapshot = try await programs().document(id).getDocument()
            guard snapshot.exists else { return nil }
            return try snapshot.data(as: DietProgram.self)
        } catch { throw AppError.map(error) }
    }

    // MARK: Kayıtlar ve notlar

    func uploadLog(_ log: DietMealLog) async throws {
        try await write(log, to: sub(log.programID, DietCollection.logs).document(log.id))
    }

    func deleteLog(id: String, programID: String) async throws {
        do { try await sub(programID, DietCollection.logs).document(id).delete() } catch { throw AppError.map(error) }
    }

    func fetchLogs(programID: String) async throws -> [DietMealLog] {
        do { return decode(try await sub(programID, DietCollection.logs).getDocuments(), as: DietMealLog.self) } catch { throw AppError.map(error) }
    }

    func uploadNote(_ note: DietDayNote) async throws {
        try await write(note, to: sub(note.programID, DietCollection.notes).document(note.dayKey))
    }

    func fetchNotes(programID: String) async throws -> [DietDayNote] {
        do { return decode(try await sub(programID, DietCollection.notes).getDocuments(), as: DietDayNote.self) } catch { throw AppError.map(error) }
    }

    // MARK: Yorumlar

    func addComment(_ comment: DietComment) async throws {
        try await write(comment, to: sub(comment.programID, DietCollection.comments).document(comment.id))
    }

    func deleteComment(id: String, programID: String) async throws {
        do { try await sub(programID, DietCollection.comments).document(id).delete() } catch { throw AppError.map(error) }
    }

    func fetchComments(programID: String) async throws -> [DietComment] {
        do {
            return decode(try await sub(programID, DietCollection.comments).getDocuments(), as: DietComment.self)
                .sorted { $0.createdAt < $1.createdAt }
        } catch { throw AppError.map(error) }
    }

    // MARK: Öneriler

    func createSuggestion(_ suggestion: DietSuggestion) async throws {
        try await write(suggestion, to: sub(suggestion.programID, DietCollection.suggestions).document(suggestion.id))
    }

    func fetchSuggestions(programID: String) async throws -> [DietSuggestion] {
        do {
            return decode(try await sub(programID, DietCollection.suggestions).getDocuments(), as: DietSuggestion.self)
                .sorted { $0.createdAt > $1.createdAt }
        } catch { throw AppError.map(error) }
    }

    func decideSuggestion(id: String, programID: String, status: DietSuggestionStatus, at: Date) async throws {
        do {
            try await sub(programID, DietCollection.suggestions).document(id)
                .updateData(["status": status.rawValue, "decidedAt": Timestamp(date: at)])
        } catch { throw AppError.map(error) }
    }

    // MARK: Teklifler

    func createOffer(_ offer: DietOffer) async throws {
        try await write(offer, to: db.collection(DietCollection.offers).document(offer.id))
    }

    func fetchOffer(id: String) async throws -> DietOffer? {
        do {
            let snapshot = try await db.collection(DietCollection.offers).document(id).getDocument()
            guard snapshot.exists else { return nil }
            return try snapshot.data(as: DietOffer.self)
        } catch { throw AppError.map(error) }
    }

    func decideOffer(id: String, status: DietOfferStatus, programID: String?, at: Date) async throws {
        var fields: [String: Any] = ["status": status.rawValue, "decidedAt": Timestamp(date: at)]
        if let programID { fields["acceptedProgramID"] = programID }
        do { try await db.collection(DietCollection.offers).document(id).updateData(fields) } catch { throw AppError.map(error) }
    }

    // MARK: Hesap silme

    func purge(userID: String) async throws {
        for program in try await fetchMyPrograms(userID: userID) {
            try await deleteProgram(id: program.id)
        }
        do {
            let offers = try db.collection(DietCollection.offers)
            for field in ["fromID", "toID"] {
                for document in try await offers.whereField(field, isEqualTo: userID).getDocuments().documents {
                    try await document.reference.delete()
                }
            }
            // Başkalarının programında bıraktığım yorumlar ve öneriler.
            for program in try await fetchSharedPrograms(viewerID: userID) {
                for name in [DietCollection.comments, DietCollection.suggestions] {
                    for document in try await sub(program.id, name).whereField("authorID", isEqualTo: userID).getDocuments().documents {
                        try? await document.reference.delete()
                    }
                }
            }
        } catch {
            throw AppError.map(error)
        }
    }

    private func deleteAll(in collection: CollectionReference) async throws {
        while true {
            let snapshot = try await collection.limit(to: 400).getDocuments()
            guard !snapshot.documents.isEmpty else { return }
            let batch = try db.batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
        }
    }
}
