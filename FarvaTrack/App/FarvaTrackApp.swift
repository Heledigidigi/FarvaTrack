import SwiftUI
import WidgetKit
import SwiftData

@main
struct FarvaTrackApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    @State private var authViewModel: AuthViewModel

    init() {
        // Plist yoksa başlatılmaz; uygulama kurulum ekranıyla açılır (çökmez).
        FirebaseBootstrap.configureIfPossible()

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
                WorkoutTemplate.self,
                TrainingProgram.self,
                ManualStepEntry.self,
                ChatMessageRecord.self,
                ChatPendingOperation.self,
                StickerRecord.self,
                ChatPlacementRecord.self,
                BubbleStyleRecord.self
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

    /// Görünüm teması (Ayarlar → Görünüm); varsayılan klasik.
    @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.default.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if FirebaseBootstrap.isConfigured {
                    ContentView()
                        .environment(authViewModel)
                } else {
                    FirebaseSetupView()
                }
            }
            .preferredColorScheme(AppTheme.resolve(themeRaw).colorScheme)
            .tint(Color.ftAccentLight)
            // Uygulama güncellenince ana ekrandaki widget'lar yeni tasarımla yeniden çizilsin.
            .task { WidgetCenter.shared.reloadAllTimelines() }
        }
        .modelContainer(modelContainer)
    }
}
