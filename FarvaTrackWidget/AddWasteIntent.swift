import AppIntents

/// Biyolojik atık widget'ındaki +1 butonu. Kaydı App Group kuyruğuna yazar; uygulama açılınca aktarılır.
struct AddWasteIntent: AppIntent {
    static var title: LocalizedStringResource = "Kayıt Ekle"
    static var description = IntentDescription("Bugünkü sayacı bir artırır.")

    init() {}

    func perform() async throws -> some IntentResult {
        SharedStore.addWasteFromWidget()
        return .result()
    }
}
