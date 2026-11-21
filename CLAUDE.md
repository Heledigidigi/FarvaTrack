# FarvaTrack: proje rehberi

iOS 17+ fitness ve sağlık takip uygulaması. Swift 5 dil modu, SwiftUI, MVVM, `@Observable`, async/await, SwiftData (çevrimdışı), Firebase (Auth, Firestore, Storage). Arayüz metinleri ve kod yorumları **Türkçe**.

## Derleme ve doğrulama

- Proje dosyası repoda yok; `project.yml` (XcodeGen) tek kaynaktır. Hedefler: `FarvaTrack` (uygulama), `FarvaTrackWidget` (WidgetKit uzantısı), `FarvaTrackTests`.
- Linux ortamında Swift/Xcode derlenemez. Doğrulama **GitHub Actions** ile yapılır (`.github/workflows/build.yml`): her push'ta cihaz için Release derlemesi, simülatörde testler, ad-hoc imzalı IPA.
- CI sonuçları her çalıştırmada **`ci-logs` branch'ine** yazılır: `STATUS.txt`, `build-errors.txt`, `test-summary.txt`, tam `build.log` / `test.log`. Okumak için: `git fetch --depth=1 origin ci-logs && git show FETCH_HEAD:STATUS.txt`.
- Çalışma akışı: özellik branch'inde çalış → push → `ci-logs`'ta o commit'in sonucunu bekle → yeşilse `main`'e hızlı ileri birleştir.

## Mimari kuralları

- Her modül: `Features/<Modül>/{Models,ViewModels,Views}`. ViewModel'ler `@MainActor @Observable final class`.
- Servisler protokol arkasında (`FirebaseServicing`, `WorkoutSyncing`, `HealthDataProviding`); testler sahte uygulamalarla yazılır.
- Kayıt deseni: SwiftData ana kaynak; `needsSync` bayrağı + arka planda Firestore yüklemesi; silmeler `PendingDeletionStore` ile kuyruklanır; çakışmada bekleyen yerel değişiklik kazanır, yoksa `updatedAt` daha yeni olan.
- Firestore yolları `users/{uid}/<koleksiyon>`; genel işlemler `FirestoreCollectionClient` üzerinden. Kurallar `firebase/firestore.rules`.
- Firebase yalnızca `GoogleService-Info.plist` varsa başlar (`FirebaseBootstrap`); yoksa uygulama kurulum ekranıyla açılır. Plist CI'da `GOOGLE_SERVICE_INFO_PLIST` secret'ından yazılır, repoya eklenmez.
- `SharedStore.swift` hem uygulama hem widget hedefinde derlenir; uygulamaya özel tiplere bağımlı olmamalı. App Group: `group.com.farvatrack.shared`.
- Renkler `Color.ft*` (koyu tema, bordo vurgu). Önemli aksiyonlarda `Haptics`, VoiceOver etiketleri zorunlu.
- Sağlık içeriğinde güvenlik: 18 yaş altına kilo verme hedefi yok, BMI 18,5 altı hedef engellenir, tıbbi tavsiye dili kullanılmaz.

## Yol haritası

| Aşama | İçerik | Durum |
|---|---|---|
| 1 | Giriş/kayıt, onboarding, sekmeler, Özet | Tamam |
| 2 | Egzersiz (CRUD), adım + HealthKit, adım widget'ı | Tamam |
| 3 | Beslenme, su (animasyonlu + etkileşimli widget, hatırlatıcı), uyku, kilo ve ölçüler | Tamam |
| 4 | Biyolojik atık sayacı (yalnızca `role: admin`), istatistikler, rozetler, hatırlatıcı merkezi | Sırada |
| 5 | Profil düzenleme, ayarlar, hesap silme, kütüphane senkronu, imzalama/TestFlight | Sırada |

Henüz eklenmeyen modüller `ComingSoonView` ile görünür; `AppRoute.destination` ve sekme görünümleri modül geldikçe bağlanır.
