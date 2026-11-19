import SwiftUI
import Observation
import SwiftData

enum AuthState: Equatable {
    case loading
    case unauthenticated
    case onboarding
    case authenticated
}

@Observable
final class AuthViewModel {
    var authState: AuthState = .authenticated
    var currentUser: AppUser?
    var errorMessage: String?

    private let service: FirebaseManager
    private let modelContext: ModelContext

    init(service: FirebaseManager, modelContext: ModelContext) {
        self.service = service
        self.modelContext = modelContext
        self.currentUser = AppUser(
            uid: "demo_user_1",
            email: "demo@farvatrack.com",
            displayName: "Özgür"
        )
    }

    func start() {
        // Oturum durumu kontrolü
        authState = .authenticated
    }

    func signOut() {
        authState = .unauthenticated
        currentUser = nil
    }
}
