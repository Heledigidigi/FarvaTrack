import SwiftUI

// MARK: - Sohbet teması (Aşama 10)
//
// Tema oda başına seçilir ve iki tarafta da aynı görünür: `chats/{id}.theme = {id, variant, by, at}`.
// Tema; duvar kâğıdını (animasyonlu), üst/alt çubukları, düğmeleri ve varsayılan baloncuğu değiştirir.
// Kişi kendi özel baloncuğunu seçtiyse onun mesajları o baloncukla kalır (tema yalnızca varsayılanı boyar).

enum ChatThemeID: String, Codable, CaseIterable, Identifiable {
    /// Uygulama temasının zemini ve renkleri (Klasik / Koyu).
    case plain = "varsayilan"
    case rainbow = "gokkusagi"
    case pixelMeadow = "cayir"
    case hillCat = "kedi"

    var id: Self { self }

    var title: String {
        switch self {
        case .plain: return "Varsayılan"
        case .rainbow: return "Gökkuşağı Cenneti"
        case .pixelMeadow: return "Piksel Çayır"
        case .hillCat: return "Tepedeki Kedi"
        }
    }

    var subtitle: String {
        switch self {
        case .plain: return "Uygulamanın görünümü"
        case .rainbow: return "Parıltılar, güneş ışınları, süzülen tüyler"
        case .pixelMeadow: return "Güneş ve ay saate göre hareket eder"
        case .hillCat: return "Gerçekçi gökyüzü, akan bulutlar"
        }
    }

    /// Seçicideki küçük resim (`Assets`).
    var thumbnailAsset: String? {
        switch self {
        case .plain: return nil
        case .rainbow: return "TemaGokkusagi"
        case .pixelMeadow: return "TemaCayirOnizleme"
        case .hillCat: return "TemaKediOnizleme"
        }
    }
}

/// Tepedeki Kedi'nin gökyüzü seçenekleri.
enum ChatHillSky: String, Codable, CaseIterable, Identifiable {
    case golden = "altin"
    case rose = "gul"
    case fire = "ates"

    var id: Self { self }

    var title: String {
        switch self {
        case .golden: return "Altın saat"
        case .rose: return "Gül alacakaranlık"
        case .fire: return "Ateşli gün batımı"
        }
    }
}

/// Odada seçili tema. `by`: seçen üye.
struct ChatThemeChoice: Codable, Equatable {
    var id: ChatThemeID
    var variant: String?
    var by: String
    var at: Date

    var hillSky: ChatHillSky { variant.flatMap(ChatHillSky.init(rawValue:)) ?? .golden }

    /// Aynı görünüm mü (kim/ne zaman seçtiğinden bağımsız).
    func sameLook(as other: ChatThemeChoice?) -> Bool {
        guard let other else { return id == .plain }
        return id == other.id && (id != .hillCat || hillSky == other.hillSky)
    }

    static let maxVariantLength = 16
}

// MARK: - Renk yardımcıları

/// Doğrusal ara değer bulmaya uygun RGBA (0…1).
struct ThemeRGBA: Equatable {
    var r: Double, g: Double, b: Double, a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// "#RRGGBB" + saydamlık.
    init(hex: String, alpha: Double = 1) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255, alpha)
    }

    /// 0–255 bileşenlerle.
    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> ThemeRGBA {
        ThemeRGBA(r / 255, g / 255, b / 255, a)
    }

    func mixed(with other: ThemeRGBA, _ t: Double) -> ThemeRGBA {
        let t = min(1, max(0, t))
        return ThemeRGBA(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var simd: SIMD4<Float> { SIMD4(Float(r), Float(g), Float(b), Float(a)) }
}

// MARK: - Görünüm (çubuklar, düğmeler, varsayılan baloncuk)

enum ChatThemeFill: Equatable {
    case solid(ThemeRGBA)
    /// Sol üstten sağ alta.
    case gradient([ThemeRGBA])

    var style: AnyShapeStyle {
        switch self {
        case .solid(let color): return AnyShapeStyle(color.color)
        case .gradient(let colors):
            return AnyShapeStyle(LinearGradient(colors: colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

/// Sohbeti duvar kâğıdından ayıran ince çizgi.
enum ChatThemeSeparator: Equatable {
    case color(ThemeRGBA, width: CGFloat)
    case gradient([ThemeRGBA], width: CGFloat)

    var width: CGFloat {
        switch self {
        case .color(_, let width), .gradient(_, let width): return width
        }
    }

    var style: AnyShapeStyle {
        switch self {
        case .color(let color, _): return AnyShapeStyle(color.color)
        case .gradient(let colors, _):
            return AnyShapeStyle(LinearGradient(colors: colors.map(\.color), startPoint: .leading, endPoint: .trailing))
        }
    }
}

struct ChatThemeLook: Equatable {
    var colorScheme: ColorScheme
    var chrome: ThemeRGBA
    var chromeText: ThemeRGBA
    var secondaryText: ThemeRGBA
    var icon: ThemeRGBA
    var separator: ChatThemeSeparator
    var dayBackground: ThemeRGBA
    var dayText: ThemeRGBA
    var field: ThemeRGBA
    var fieldText: ThemeRGBA
    var send: ChatThemeFill
    var sendText: ThemeRGBA
    var outgoing: ChatThemeFill
    var outgoingText: ThemeRGBA
    var incoming: ChatThemeFill
    var incomingText: ThemeRGBA
    /// Baloncuk köşesi; kuyruk tarafındaki alt köşe `tailRadius`.
    var cornerRadius: CGFloat = 18
    var tailRadius: CGFloat = 6
    /// Piksel temasında baloncuğun altındaki blok gölgesi (0 = yok).
    var blockShade: Double = 0
    /// Gelen baloncuğun arkasında buzlu cam. Animasyonlu zeminde her karede yeniden bulanıklaştırıldığı için kapalı.
    var incomingBlur: Bool = false
    /// Tepedeki Kedi: baloncuk rengi güneşe uzaklığa göre (bkz. `ChatThemeSun`).
    var sunPalette: ChatThemeSunPalette?

    static func look(for choice: ChatThemeChoice?, date: Date = .now, clock: PixelMeadowClock = .init()) -> ChatThemeLook? {
        guard let choice else { return nil }
        switch choice.id {
        case .plain: return nil
        case .rainbow: return .rainbow
        case .pixelMeadow: return clock.isNight(at: date) ? .pixelNight : .pixelDay
        case .hillCat:
            switch choice.hillSky {
            case .golden: return .hillGolden
            case .rose: return .hillRose
            case .fire: return .hillFire
            }
        }
    }

    // Önizlemede onaylanan değerler.
    static let rainbow = ChatThemeLook(
        colorScheme: .light,
        chrome: .rgb(255, 240, 248, 0.66), chromeText: ThemeRGBA(hex: "#5B2C55"), secondaryText: ThemeRGBA(hex: "#A0569A"),
        icon: ThemeRGBA(hex: "#C2569A"),
        separator: .gradient(["#FFADC9", "#FFD2A6", "#FFF3A8", "#BFF0C0", "#A6E6FF", "#C4B5FF", "#FFBDF2"].map { ThemeRGBA(hex: $0) }, width: 1.5),
        dayBackground: .rgb(255, 255, 255, 0.55), dayText: ThemeRGBA(hex: "#8A3F7C"),
        field: .rgb(255, 255, 255, 0.8), fieldText: ThemeRGBA(hex: "#B0809F"),
        send: .gradient([ThemeRGBA(hex: "#FF8FC6"), ThemeRGBA(hex: "#A98CFF")]), sendText: .rgb(255, 255, 255),
        outgoing: .gradient([ThemeRGBA(hex: "#FF8FC6"), ThemeRGBA(hex: "#C58CFF"), ThemeRGBA(hex: "#8FB6FF")]), outgoingText: .rgb(255, 255, 255),
        incoming: .solid(.rgb(255, 255, 255, 0.8)), incomingText: ThemeRGBA(hex: "#4D2448")
    )

    static let pixelDay = ChatThemeLook(
        colorScheme: .light,
        chrome: .rgb(246, 240, 224, 0.82), chromeText: ThemeRGBA(hex: "#2F2A1E"), secondaryText: ThemeRGBA(hex: "#4D7A2A"),
        icon: ThemeRGBA(hex: "#4D7A2A"),
        separator: .color(ThemeRGBA(hex: "#6B4A2B"), width: 2),
        dayBackground: ThemeRGBA(hex: "#7A5636"), dayText: ThemeRGBA(hex: "#FFF6DF"),
        field: ThemeRGBA(hex: "#FFFAF0"), fieldText: ThemeRGBA(hex: "#9B927F"),
        send: .solid(ThemeRGBA(hex: "#5F9B37")), sendText: .rgb(255, 255, 255),
        outgoing: .solid(ThemeRGBA(hex: "#5F9B37")), outgoingText: .rgb(255, 255, 255),
        incoming: .solid(ThemeRGBA(hex: "#EFE8D4")), incomingText: ThemeRGBA(hex: "#2F2A1E"),
        cornerRadius: 3, tailRadius: 3, blockShade: 0.14
    )

    static let pixelNight = ChatThemeLook(
        colorScheme: .dark,
        chrome: .rgb(18, 24, 48, 0.82), chromeText: ThemeRGBA(hex: "#E6EAFF"), secondaryText: ThemeRGBA(hex: "#9FB4FF"),
        icon: ThemeRGBA(hex: "#9FB4FF"),
        separator: .color(ThemeRGBA(hex: "#2C3566"), width: 2),
        dayBackground: ThemeRGBA(hex: "#2C3566"), dayText: ThemeRGBA(hex: "#DFE5FF"),
        field: ThemeRGBA(hex: "#1C2340"), fieldText: ThemeRGBA(hex: "#7C87B5"),
        send: .solid(ThemeRGBA(hex: "#3E5FAE")), sendText: .rgb(255, 255, 255),
        outgoing: .solid(ThemeRGBA(hex: "#3E5FAE")), outgoingText: .rgb(255, 255, 255),
        incoming: .solid(ThemeRGBA(hex: "#2A3150")), incomingText: ThemeRGBA(hex: "#E6EAFF"),
        cornerRadius: 3, tailRadius: 3, blockShade: 0.25
    )

    static let hillGolden = ChatThemeLook(
        colorScheme: .light,
        chrome: .rgb(255, 240, 222, 0.62), chromeText: ThemeRGBA(hex: "#3E2A24"), secondaryText: ThemeRGBA(hex: "#9A6A52"),
        icon: ThemeRGBA(hex: "#B8642E"),
        separator: .color(.rgb(255, 255, 255, 0.45), width: 1),
        dayBackground: .rgb(255, 236, 214, 0.6), dayText: ThemeRGBA(hex: "#7A4A33"),
        field: .rgb(255, 250, 244, 0.85), fieldText: ThemeRGBA(hex: "#B0907E"),
        send: .solid(ThemeRGBA(hex: "#C9683F")), sendText: .rgb(255, 255, 255),
        outgoing: .gradient([ThemeRGBA(hex: "#E5935A"), ThemeRGBA(hex: "#C9683F")]), outgoingText: .rgb(255, 255, 255),
        incoming: .solid(.rgb(255, 246, 236, 0.82)), incomingText: ThemeRGBA(hex: "#3E2A24"),
        sunPalette: .golden
    )

    static let hillRose = ChatThemeLook(
        colorScheme: .dark,
        chrome: .rgb(52, 40, 86, 0.55), chromeText: ThemeRGBA(hex: "#FBEAF3"), secondaryText: ThemeRGBA(hex: "#E8B6D6"),
        icon: ThemeRGBA(hex: "#FFB8D0"),
        separator: .color(.rgb(255, 255, 255, 0.14), width: 1),
        dayBackground: .rgb(60, 46, 96, 0.55), dayText: ThemeRGBA(hex: "#F6D9EA"),
        field: .rgb(40, 30, 70, 0.6), fieldText: ThemeRGBA(hex: "#BBA6CF"),
        send: .gradient([ThemeRGBA(hex: "#F29AB9"), ThemeRGBA(hex: "#B178E0")]), sendText: .rgb(255, 255, 255),
        outgoing: .gradient([ThemeRGBA(hex: "#E889AD"), ThemeRGBA(hex: "#A56AD0")]), outgoingText: .rgb(255, 255, 255),
        incoming: .solid(.rgb(66, 52, 104, 0.72)), incomingText: ThemeRGBA(hex: "#FBEAF3"),
        sunPalette: .rose
    )

    static let hillFire = ChatThemeLook(
        colorScheme: .dark,
        chrome: .rgb(66, 30, 40, 0.52), chromeText: ThemeRGBA(hex: "#FFF0E2"), secondaryText: ThemeRGBA(hex: "#F6C3A0"),
        icon: ThemeRGBA(hex: "#FFB47A"),
        separator: .color(.rgb(255, 200, 160, 0.18), width: 1),
        dayBackground: .rgb(80, 34, 44, 0.55), dayText: ThemeRGBA(hex: "#FFE1C8"),
        field: .rgb(56, 24, 34, 0.6), fieldText: ThemeRGBA(hex: "#D6A68C"),
        send: .gradient([ThemeRGBA(hex: "#FFA75A"), ThemeRGBA(hex: "#E0503A")]), sendText: .rgb(255, 255, 255),
        outgoing: .gradient([ThemeRGBA(hex: "#FF9A4D"), ThemeRGBA(hex: "#D9443A")]), outgoingText: .rgb(255, 255, 255),
        incoming: .solid(.rgb(82, 38, 50, 0.72)), incomingText: ThemeRGBA(hex: "#FFF0E2"),
        sunPalette: .fire
    )
}

// MARK: - Tepedeki Kedi: güneşe uzaklığa göre baloncuk rengi

struct ChatThemeSunPalette: Equatable {
    /// Giden: güneşe yakın / uzak; her biri iki renkli geçiş (güneşe bakan sağ üst köşe ilk renk).
    var outgoingNear: [ThemeRGBA]
    var outgoingFar: [ThemeRGBA]
    var incomingNear: ThemeRGBA
    var incomingFar: ThemeRGBA

    static let golden = ChatThemeSunPalette(
        outgoingNear: [ThemeRGBA(hex: "#F7BB80"), ThemeRGBA(hex: "#E8955A")],
        outgoingFar: [ThemeRGBA(hex: "#CF7243"), ThemeRGBA(hex: "#A5512E")],
        incomingNear: .rgb(255, 247, 236, 0.9), incomingFar: .rgb(238, 218, 202, 0.84))
    static let rose = ChatThemeSunPalette(
        outgoingNear: [ThemeRGBA(hex: "#F8ACC6"), ThemeRGBA(hex: "#DC90D2")],
        outgoingFar: [ThemeRGBA(hex: "#C46A9C"), ThemeRGBA(hex: "#875ABD")],
        incomingNear: .rgb(98, 78, 138, 0.72), incomingFar: .rgb(42, 32, 78, 0.8))
    static let fire = ChatThemeSunPalette(
        outgoingNear: [ThemeRGBA(hex: "#FFBE6A"), ThemeRGBA(hex: "#F4814A")],
        outgoingFar: [ThemeRGBA(hex: "#DC5C3C"), ThemeRGBA(hex: "#A12F39")],
        incomingNear: .rgb(118, 56, 60, 0.72), incomingFar: .rgb(56, 22, 34, 0.82))

    func outgoing(_ t: Double) -> [ThemeRGBA] {
        zip(outgoingNear, outgoingFar).map { $0.mixed(with: $1, t) }
    }

    func incoming(_ t: Double) -> ThemeRGBA { incomingNear.mixed(with: incomingFar, t) }
}

enum ChatThemeSun {
    /// Duvar kâğıdındaki güneşin yeri (görsel uzayında, 736 × 1472).
    static let imageSize = CGSize(width: 736, height: 1472)
    static let sunInImage = CGPoint(x: 705, y: 120)

    /// Ekranı dolduran (aspect fill) görselde güneşin ekran konumu.
    static func sunPoint(in size: CGSize) -> CGPoint {
        let fill = AspectFill(image: imageSize, container: size)
        return fill.point(sunInImage)
    }

    /// 0 = güneşe yakın, 1 = en uzak. Ekranın üst çeyreği hep "yakın", sol alt köşe "uzak".
    static func distanceFactor(center: CGPoint, sun: CGPoint, screen: CGSize) -> Double {
        let maxDistance = max(1, hypot(screen.width, screen.height) * 0.95)
        let ratio = hypot(center.x - sun.x, center.y - sun.y) / maxDistance
        return min(1, max(0, (ratio - 0.38) / 0.55))
    }
}

/// Görseli kabı dolduracak biçimde ölçekleyip ortalar (taşan kenarlar kırpılır).
struct AspectFill: Equatable {
    let scale: CGFloat
    let origin: CGPoint

    init(image: CGSize, container: CGSize) {
        let scale = max(container.width / max(image.width, 1), container.height / max(image.height, 1))
        self.scale = scale
        origin = CGPoint(x: (container.width - image.width * scale) / 2, y: (container.height - image.height * scale) / 2)
    }

    func point(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
    func rect(_ r: CGRect) -> CGRect { CGRect(origin: point(r.origin), size: CGSize(width: r.width * scale, height: r.height * scale)) }
}

// MARK: - Piksel Çayır: saate göre gökyüzü

/// Güneşin doğuşu/batışı mevsime göre hesaplanır (konum istenmez: enlem 41°, boylam saat diliminden; İstanbul 29°).
/// Gökyüzü renkleri 06:30 doğuş / 19:00 batış varsayılarak tanımlı "sanal saat"e göre seçilir; gerçek saat
/// günün doğuş–batış aralığına göre bu sanal saate eşlenir.
struct PixelMeadowClock {
    var latitude: Double = 41
    var timeZone: TimeZone = .current
    static let virtualRise = 6.5
    static let virtualSet = 19.0

    /// Yerel saatle doğuş ve batış (saat cinsinden, ör. 7.25).
    func sunTimes(on date: Date) -> (rise: Double, set: Double) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 172)
        let declination = 23.44 * sin((360.0 / 365.0 * (day - 81)) * .pi / 180)
        let phi = latitude * .pi / 180, delta = declination * .pi / 180
        let cosH = (sin(-0.833 * .pi / 180) - sin(phi) * sin(delta)) / (cos(phi) * cos(delta))
        let hourAngle = acos(min(1, max(-1, cosH))) * 180 / .pi
        let b = 2 * .pi * (day - 81) / 364
        let equationOfTime = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)  // dakika
        let offsetHours = Double(timeZone.secondsFromGMT(for: date)) / 3600
        // Türkiye UTC+3 kullanır ama ~29° D'dadır; diğer bölgelerde saat diliminin merkez boylamı.
        let longitude = timeZone.identifier == "Europe/Istanbul" ? 29.0 : offsetHours * 15
        let noon = 12 + (offsetHours * 15 - longitude) / 15 - equationOfTime / 60
        return (noon - hourAngle / 15, noon + hourAngle / 15)
    }

    func localHour(_ date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    /// Gerçek saati sanal saate eşler (doğuş → 6,5, batış → 19).
    func virtualHour(at date: Date) -> Double {
        Self.virtualHour(localHour(date), rise: sunTimes(on: date).rise, set: sunTimes(on: date).set)
    }

    static func virtualHour(_ hour: Double, rise: Double, set: Double) -> Double {
        if hour >= rise && hour <= set {
            return virtualRise + (hour - rise) / (set - rise) * (virtualSet - virtualRise)
        }
        // Gece: batış → ertesi doğuş, 19 → 30,5 (24'ü geçen kısım ertesi güne).
        let nightLength = 24 - (set - rise)
        let since = hour > set ? hour - set : hour + 24 - set
        let virtual = virtualSet + since / nightLength * (24 - (virtualSet - virtualRise))
        return virtual >= 24 ? virtual - 24 : virtual
    }

    func isNight(at date: Date) -> Bool { PixelMeadowSky.nightWeight(virtualHour(at: date)) > 0.5 }
}

/// Sanal saate göre gökyüzü durumu (önizlemedeki anahtar kareler).
struct PixelMeadowSky: Equatable {
    var top: ThemeRGBA
    var horizon: ThemeRGBA
    /// Çayıra uygulanan çarpma rengi.
    var groundTint: ThemeRGBA
    var cloudBrightness: Double
    var cloudSaturation: Double
    var sunsetWeight: Double
    var nightWeight: Double

    private struct Key {
        let hour: Double, top: String, horizon: String, tint: String, brightness: Double, saturation: Double
    }

    private static let keys: [Key] = [
        Key(hour: 0, top: "#060A22", horizon: "#172048", tint: "#3B4478", brightness: 0.42, saturation: 0.08),
        Key(hour: 4.6, top: "#0A1130", horizon: "#22305C", tint: "#3F4A80", brightness: 0.45, saturation: 0.08),
        Key(hour: 5.8, top: "#2C3A6E", horizon: "#D98A7A", tint: "#9A8FB0", brightness: 0.75, saturation: 0.6),
        Key(hour: 6.8, top: "#6F8FCF", horizon: "#F4C59A", tint: "#F0DCC8", brightness: 1.0, saturation: 0.7),
        Key(hour: 8.5, top: "#78A7FF", horizon: "#C8DEFA", tint: "#EEF3FF", brightness: 1.15, saturation: 0.28),
        Key(hour: 15.5, top: "#78A7FF", horizon: "#CFE2F7", tint: "#F2F5FF", brightness: 1.15, saturation: 0.3),
        Key(hour: 17.4, top: "#8AA6D8", horizon: "#F3C99A", tint: "#FBEFE2", brightness: 1.05, saturation: 0.75),
        Key(hour: 18.4, top: "#C98AA8", horizon: "#F6B38A", tint: "#FFFFFF", brightness: 1.0, saturation: 1.0),
        Key(hour: 19.4, top: "#5A4478", horizon: "#E48E7C", tint: "#C9A7B8", brightness: 0.8, saturation: 0.8),
        Key(hour: 20.5, top: "#1B1D48", horizon: "#3D3466", tint: "#59578E", brightness: 0.52, saturation: 0.2),
        Key(hour: 21.5, top: "#060A22", horizon: "#172048", tint: "#3B4478", brightness: 0.42, saturation: 0.08),
        Key(hour: 24, top: "#060A22", horizon: "#172048", tint: "#3B4478", brightness: 0.42, saturation: 0.08)
    ]

    static func at(_ hour: Double) -> PixelMeadowSky {
        let h = min(23.999, max(0, hour))
        var i = 0
        while i + 1 < keys.count - 1, keys[i + 1].hour <= h { i += 1 }
        let a = keys[i], b = keys[i + 1]
        let t = (h - a.hour) / (b.hour - a.hour)
        return PixelMeadowSky(
            top: ThemeRGBA(hex: a.top).mixed(with: ThemeRGBA(hex: b.top), t),
            horizon: ThemeRGBA(hex: a.horizon).mixed(with: ThemeRGBA(hex: b.horizon), t),
            groundTint: ThemeRGBA(hex: a.tint).mixed(with: ThemeRGBA(hex: b.tint), t),
            cloudBrightness: a.brightness + (b.brightness - a.brightness) * t,
            cloudSaturation: a.saturation + (b.saturation - a.saturation) * t,
            sunsetWeight: sunsetWeight(h),
            nightWeight: nightWeight(h)
        )
    }

    /// Gün batımında görselin orijinal gökyüzü görünür.
    static func sunsetWeight(_ h: Double) -> Double {
        if h < 17.7 { return 0 }
        if h < 18.4 { return (h - 17.7) / 0.7 }
        if h < 19.0 { return 1 }
        if h < 19.6 { return 1 - (h - 19.0) / 0.6 }
        return 0
    }

    static func nightWeight(_ h: Double) -> Double {
        if h >= 21 || h < 4.6 { return 1 }
        if h < 5.8 { return 1 - (h - 4.6) / 1.2 }
        if h > 19.6 { return (h - 19.6) / 1.4 }
        return 0
    }

    /// Güneş (gündüz) ya da ay (gece) yayı: 0 doğuş (sağ) … 1 batış (sol). Görsel uzayında (600 × 1200).
    static func bodyPosition(_ t: Double) -> CGPoint {
        CGPoint(x: 560 - 520 * t, y: 505 - sin(.pi * t) * 420)
    }

    static func sunProgress(_ h: Double) -> Double? {
        let rise = PixelMeadowClock.virtualRise, set = PixelMeadowClock.virtualSet
        guard h >= rise - 0.4, h <= set + 0.4 else { return nil }
        return (h - rise) / (set - rise)
    }

    static func moonProgress(_ h: Double) -> Double? {
        let rise = 19.9, set = 5.9, length = 24 - rise + set
        if h >= rise { return (h - rise) / length }
        if h <= set { return (h + 24 - rise) / length }
        return nil
    }
}

// MARK: - Ortam değerleri

private struct ChatThemeLookKey: EnvironmentKey { static let defaultValue: ChatThemeLook? = nil }
/// Ekranda (pencere koordinatında) güneşin yeri ve ekran boyutu: kedi temasında baloncuk rengi için.
struct ChatThemeSunInfo: Equatable {
    var sun: CGPoint
    var screen: CGSize
}
private struct ChatThemeSunKey: EnvironmentKey { static let defaultValue: ChatThemeSunInfo? = nil }

extension EnvironmentValues {
    var chatThemeLook: ChatThemeLook? {
        get { self[ChatThemeLookKey.self] }
        set { self[ChatThemeLookKey.self] = newValue }
    }
    var chatThemeSun: ChatThemeSunInfo? {
        get { self[ChatThemeSunKey.self] }
        set { self[ChatThemeSunKey.self] = newValue }
    }
}

// MARK: - Küçük parçalar için renk takımı

/// Sohbetin bütün küçük parçaları (paneller, ses kaydı, yanıt/bul çubukları, sesli mesaj…) bu renkleri kullanır;
/// tema yoksa uygulamanın renkleri. Yeni bir parça eklerken `Color.ft*` yerine `@Environment(\.chatTint)` kullan.
struct ChatTint {
    /// Panel zemini (sticker / galeri): çubuk rengi, neredeyse opak.
    var panel: Color
    var chrome: Color
    /// Vurgu (seçim, ilerleme, kayıt çubuğu dalga formu).
    var accent: Color
    /// Simgeler ve vurgulu yazılar.
    var icon: Color
    /// Kart / alan zemini (yazma alanı, kayıt çubuğu, küçük düğme zemini).
    var field: Color
    var text: Color
    var secondary: Color
    /// Silik dolgu (tutamaç, boş hücre).
    var subtle: Color
    /// Vurgu üstündeki yazı (seçim numarası, düğme).
    var onAccent: Color
    var colorScheme: ColorScheme?
    /// Alan köşesi (Piksel Çayır'da köşeli).
    var corner: CGFloat = 19

    static let app = ChatTint(panel: .ftChrome, chrome: .ftChrome, accent: .ftAccent, icon: .ftAccentLight,
                              field: .ftCardElevated, text: .ftText, secondary: .ftTextSecondary,
                              subtle: .ftSubtle(0.35), onAccent: .white, colorScheme: nil)

    init(panel: Color, chrome: Color, accent: Color, icon: Color, field: Color, text: Color, secondary: Color,
         subtle: Color, onAccent: Color, colorScheme: ColorScheme?) {
        self.panel = panel; self.chrome = chrome; self.accent = accent; self.icon = icon; self.field = field
        self.text = text; self.secondary = secondary; self.subtle = subtle; self.onAccent = onAccent; self.colorScheme = colorScheme
    }

    init(look: ChatThemeLook) {
        var panel = look.chrome
        panel.a = max(panel.a, 0.96)
        let accent: ThemeRGBA
        switch look.send {
        case .solid(let color): accent = color
        case .gradient(let colors): accent = colors.first ?? look.icon
        }
        self.init(panel: panel.color, chrome: look.chrome.color, accent: accent.color, icon: look.icon.color,
                  field: look.field.color, text: look.chromeText.color, secondary: look.secondaryText.color,
                  subtle: look.secondaryText.color.opacity(0.3), onAccent: look.sendText.color, colorScheme: look.colorScheme)
        corner = look.cornerRadius < 6 ? 3 : 19
    }
}

private struct ChatTintKey: EnvironmentKey { static let defaultValue = ChatTint.app }

extension EnvironmentValues {
    var chatTint: ChatTint {
        get { self[ChatTintKey.self] }
        set { self[ChatTintKey.self] = newValue }
    }
}
