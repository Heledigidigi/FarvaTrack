import AppIntents

/// Widget'taki su butonu. Kaydı App Group kuyruğuna yazar; uygulama açılınca SwiftData'ya aktarılır.
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Su Ekle"
    static var description = IntentDescription("Bugünkü su miktarına ekleme yapar.")

    @Parameter(title: "Miktar (ml)")
    var amountMl: Int

    init() { amountMl = 200 }
    init(amountMl: Int) { self.amountMl = amountMl }

    func perform() async throws -> some IntentResult {
        SharedStore.addWaterFromWidget(amountMl: amountMl)
        return .result()
    }
}
