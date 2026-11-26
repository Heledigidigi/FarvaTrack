import AppIntents
import WidgetKit

// Widget'taki düğmelerin eylemleri (yalnız widget hedefinde).

/// Halkaya dokununca gösterilen değeri değiştirir: adım → km → kcal.
struct CycleStepsMetricIntent: AppIntent {
    static var title: LocalizedStringResource = "Gösterimi Değiştir"
    static var description = IntentDescription("Adım, kilometre ve kalori arasında geçiş yapar.")

    init() {}

    func perform() async throws -> some IntentResult {
        SharedStore.cycleStepsMetric()
        return .result()
    }
}

/// Ritim widget'ındaki "Geri al" düğmesi.
struct UndoWasteIntent: AppIntent {
    static var title: LocalizedStringResource = "Geri Al"
    static var description = IntentDescription("Widget'tan eklenen son kaydı geri alır.")

    init() {}

    func perform() async throws -> some IntentResult {
        SharedStore.undoLastWasteFromWidget()
        return .result()
    }
}

/// Su widget'ındaki "Geri al" düğmesi.
struct UndoWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Suyu Geri Al"
    static var description = IntentDescription("Widget'tan eklenen son suyu geri alır.")

    init() {}

    func perform() async throws -> some IntentResult {
        SharedStore.undoLastWaterFromWidget()
        return .result()
    }
}
