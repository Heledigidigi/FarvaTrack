import SwiftUI
import SwiftData

@main
struct FarvaTrackApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    @State private var authViewModel: AuthViewModel

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: LocalUserProfile.self,
                Workout.self,
                WorkoutEntry.self,
                Exercise.self,
                MealEntry.self,
                CustomFood.self,
                FavoriteFood.self,
                WaterEntry.self,
                SleepEntry.self,
                WeightEntry.self,
                MeasurementEntry.self,
                WasteEntry.self,
                BadgeUnlock.self
            )
        } catch {
            fatalError("SwiftData ModelContainer oluşturulamadı: \(error)")
        }
        modelContainer = container

        _authViewModel = State(
            initialValue: AuthViewModel(
                service: FirebaseManager.shared,
                modelContext: container.mainContext
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
                .preferredColorScheme(.dark)
                .tint(Color.ftAccentLight)
        }
        .modelContainer(modelContainer)
    }
}