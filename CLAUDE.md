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
- TestFlight: `.github/workflows/testflight.yml` elle çalıştırılır; App Store Connect API anahtarıyla otomatik imzalar ve yükler (secret'lar README'de).
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
| 4 | Biyolojik atık sayacı (herkese açık; yönetici yalnızca günlük toplamları görür), istatistikler, rozetler, hatırlatıcı merkezi | Tamam |
| 5 | Profil düzenleme, ayarlar, hesap silme, kütüphane senkronu, imzalama/TestFlight | Tamam |
| 6 | Antrenman şablonları, haftalık/döngü programları, hazır programlar, salonda canlı mod (dinlenme sayacı), elle adım girişi | Tamam |
| 7 | Antrenman hatırlatıcısı, program uyumu istatistiği ve rozetleri, egzersiz form ipuçları (metin + SF Symbols; telifi belirsiz fotoğraf kullanılmaz), ölçülerde bilek/ön kol ve karşılaştırmalı grafik | Tamam |
| 8 | Sohbet: iki kişilik özel sohbet (alt aşamalar 8A–8H aşağıda) | Planlandı |


### Aşama 8: Sohbet (plan)

İki kişilik özel sohbet modülü (`Features/Chat`). Ücretli Apple Developer hesabı alınacakmış gibi tasarlanır: APNs, CallKit ve PushKit kodda hazır olur; hesap gelene kadar bu yetenekler kapalı/uyarılı çalışır, ücretsiz imzalı kurulumda uygulama çökmez.

**8A: Temel sohbet**
- İki kullanıcı arasında tek bir sohbet odası; Firestore `chats/{chatId}/messages` ve yalnızca iki katılımcının okuyup yazabildiği kurallar.
- Metin mesajı gönderme/alma, anlık dinleyici (snapshot listener), SwiftData'da çevrimdışı önbellek ve gönderilemeyenler için kuyruk.
- Mesaj durumları: gönderiliyor, iletildi, okundu; "yazıyor…" göstergesi.
- Mesaj silme (benden/herkesten), yanıtlama (alıntı) ve kopyalama.
- Hesap silme ve veri dışa aktarmaya sohbet verisinin eklenmesi.

**8B: Medya + kamera**
- Fotoğraf ve videoyu kalite kaybı olmadan gönderme (orijinal dosya Firebase Storage'a; sohbette önizleme küçük resmi).
- WhatsApp benzeri anlık kamera: sohbetten tek dokunuşla foto çek / basılı tutarak video kaydet.
- Yükleme ilerlemesi, iptal ve yeniden deneme; büyük dosyalar için arka planda yükleme.
- Tam ekran görüntüleyici (yakınlaştırma, video oynatma) ve cihaza kaydetme.

**8C: Sesli mesaj**
- Basılı tutarak kayıt, yukarı kaydırarak kilitleme, sola kaydırarak iptal.
- Kayıt sırasında ve oynatmada dalga formu; oynatma hızı (1x / 1,5x / 2x).
- Düşük gecikme için sıkıştırılmış ses (AAC) ve anında gönderim; dinlendi bilgisi.
- Mikrofon izni ve sessiz mod/kulaklık geçişleri.

**8D: Sticker oluşturucu**
- Fotoğraftan otomatik arka plan kaldırma (Vision, cihaz üzerinde).
- Silgi ve onarma kalemleri; dokunduğun yerin biraz üstünde çalışan ofsetli fırça ve fırça boyutu ayarı.
- Kenar kontur (beyaz çerçeve) ve kırpma; şeffaf PNG/WebP olarak kaydetme.
- Kişisel sticker kütüphanesi, Firestore/Storage ile iki cihaz arasında senkron.

**8E: Sticker gönderme + serbest yerleştirme**
- Sticker panelinden gönderme; karşı tarafın sticker'ı kendi kütüphanesine kaydedebilmesi.
- Instagram gibi sohbet üzerinde serbest yerleştirme: büyütme, döndürme, sürükleme (iki parmak hareketleri).
- Yerleştirilen sticker'ın konumu/ölçeği/açısı mesajla birlikte saklanır, iki tarafta da aynı görünür.
- Sticker'a uzun basınca kaydet / sil / öne-arkaya al.

**8F: Sohbet baloncukları**
- Hazır baloncuk temaları ve kullanıcının kendi tasarladığı özel baloncuklar.
- Baloncuk düzenleyici: çizim, sticker, yazı, emoji ve efekt ekleme.
- Dokuz dilimli (9-slice) ölçekleme: mesaj uzayıp kısaldıkça baloncuğun şekli bozulmaz.
- Seçilen özel baloncuk karşı tarafa da aynen görünür (tasarım verisi mesajla/kullanıcı profiliyle senkron).

**8G: Push bildirimleri**
- APNs kaydı ve cihaz belirtecinin Firestore'a yazılması; Cloud Functions ile yeni mesajda bildirim gönderimi.
- Bildirimde yanıtlama ve okundu işaretleme (bildirim eylemleri); sessize alma ayarı.
- Rozet sayısı ve uygulama açıkken bildirim yerine uygulama içi gösterim.
- Ücretsiz imzada APNs yokken düzgün geri düşme (yalnızca uygulama açıkken anlık dinleyici).

**8H: Sesli arama**
- Yüksek kaliteli, düşük gecikmeli sesli arama (WebRTC; sinyalleşme Firestore üzerinden, gerekirse TURN sunucusu).
- CallKit ile sistem arama ekranı; PushKit VoIP bildirimiyle kilitliyken gelen arama.
- Hoparlör, sessiz, Bluetooth kulaklık geçişleri; arama süresi ve kalite göstergesi.
- Cevapsız arama kaydı ve sohbette arama geçmişi satırı.

Yeni modül eklerken: `AppRoute` (Özet'ten açılan sayfa) veya `AppTab`, SwiftData şeması (`FarvaTrackApp`), `LiveDashboardDataSource`, Firestore kuralları, `Constants.Collection.userSubcollections` (hesap silme), `LocalDataCleaner` ve `DataExporter` güncellenir.
