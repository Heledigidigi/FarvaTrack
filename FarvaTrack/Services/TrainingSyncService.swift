import Foundation

protocol TrainingSyncing {
    func uploadTemplate(_ dto: WorkoutTemplateDTO, userID: String) async throws
    func deleteTemplate(id: String, userID: String) async throws
    func fetchTemplates(userID: String) async throws -> [WorkoutTemplateDTO]

    func uploadProgram(_ dto: TrainingProgramDTO, userID: String) async throws
    func deleteProgram(id: String, userID: String) async throws
    func fetchPrograms(userID: String) async throws -> [TrainingProgramDTO]
}

final class FirestoreTrainingSyncService: TrainingSyncing {
    private let templates = FirestoreCollectionClient(collectionName: Constants.Collection.templates)
    private let programs = FirestoreCollectionClient(collectionName: Constants.Collection.programs)

    func uploadTemplate(_ dto: WorkoutTemplateDTO, userID: String) async throws {
        try await templates.upload(dto, id: dto.id, userID: userID)
    }

    func deleteTemplate(id: String, userID: String) async throws {
        try await templates.delete(id: id, userID: userID)
    }

    func fetchTemplates(userID: String) async throws -> [WorkoutTemplateDTO] {
        try await templates.fetchAll(WorkoutTemplateDTO.self, userID: userID)
    }

    func uploadProgram(_ dto: TrainingProgramDTO, userID: String) async throws {
        try await programs.upload(dto, id: dto.id, userID: userID)
    }

    func deleteProgram(id: String, userID: String) async throws {
        try await programs.delete(id: id, userID: userID)
    }

    func fetchPrograms(userID: String) async throws -> [TrainingProgramDTO] {
        try await programs.fetchAll(TrainingProgramDTO.self, userID: userID)
    }
}
