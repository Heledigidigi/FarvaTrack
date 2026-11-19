

    static func clearSteps() {
        defaults?.removeObject(forKey: stepsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: stepsWidgetKind)
    }

    /// Hesap silme / cihaz verilerini silme: tüm widget verilerini temizler.
    static func clearAll() {
        clearSteps()
        clearWater()
        clearWaste()
    }
