import AppIntents
import WidgetKit

// MARK: - Su widget'ı ayarları

/// Damla'ya tek dokunuşta eklenecek su miktarı.
enum WaterAmountOption: Int, AppEnum {
    case ml100 = 100, ml150 = 150, ml200 = 200, ml250 = 250, ml330 = 330, ml500 = 500

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Miktar"
    static var caseDisplayRepresentations: [WaterAmountOption: DisplayRepresentation] = [
        .ml100: "100 ml", .ml150: "150 ml", .ml200: "200 ml",
        .ml250: "250 ml", .ml330: "330 ml", .ml500: "500 ml"
    ]
}

/// Su widget'ının arka plan teması.
enum WaterThemeOption: String, AppEnum {
    case krem, pamukPembe, nane, lavanta, gece, bordo
    case safak, okyanus, lavantaSisi, gunBatimi, nostalji, kedi

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tema"
    static var caseDisplayRepresentations: [WaterThemeOption: DisplayRepresentation] = [
        .krem: "Krem", .pamukPembe: "Pamuk pembe", .nane: "Nane", .lavanta: "Lavanta",
        .gece: "Gece", .bordo: "Bordo", .safak: "Şafak", .okyanus: "Okyanus",
        .lavantaSisi: "Lavanta sisi", .gunBatimi: "Gün batımı", .nostalji: "Nostalji", .kedi: "Kedi"
    ]
}

struct WaterWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Damla"
    static var description = IntentDescription("Damlaya dokununca eklenecek miktarı ve temayı seç.")

    @Parameter(title: "Dokunuşta eklenecek", default: .ml250)
    var amount: WaterAmountOption

    @Parameter(title: "Arka plan", default: .krem)
    var theme: WaterThemeOption

    init() {}
}

// MARK: - Adım widget'ı ayarları

enum StepsThemeOption: String, AppEnum {
    case gece, beyaz, bordo, krem, lavanta, grafit
    case safak, okyanus, gunBatimi, aurora, nostalji, kedi

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tema"
    static var caseDisplayRepresentations: [StepsThemeOption: DisplayRepresentation] = [
        .gece: "Gece", .beyaz: "Beyaz", .bordo: "Bordo", .krem: "Krem", .lavanta: "Lavanta",
        .grafit: "Grafit", .safak: "Şafak", .okyanus: "Okyanus", .gunBatimi: "Gün batımı",
        .aurora: "Aurora", .nostalji: "Nostalji", .kedi: "Kedi"
    ]
}

struct StepsWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Adım halkası"
    static var description = IntentDescription("Halkanın temasını seç.")

    @Parameter(title: "Tema", default: .gece)
    var theme: StepsThemeOption

    init() {}
}

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

// MARK: - Ritim widget'ı ayarları

struct WasteWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Ritim"
    static var description = IntentDescription("Kedi yerine sade sayaç göstermek için gizli modu aç.")

    @Parameter(title: "Gizli mod", default: false)
    var secretMode: Bool

    init() {}
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
