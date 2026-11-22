# FarvaTrack

SwiftUI ile yazılmış fitness ve sağlık takip uygulaması (iOS 17+, MVVM, SwiftData, Firebase).

## Durum

| Aşama | İçerik | Durum |
|---|---|---|
| 1 | Giriş / kayıt (e-posta, Apple), onboarding, sekmeler, Özet ekranı | Tamam |
| 2 | Egzersiz, adım (HealthKit) ve adım widget'ı | Tamam |
| 3 | Beslenme, su, uyku, kilo | Tamam |
| 4 | Atık sayacı, istatistikler, rozetler, hatırlatıcılar | Tamam |
| 5 | Profil, ayarlar, hesap silme, kütüphane senkronu, TestFlight | Tamam |
| 6 | Antrenman şablonları ve programları, canlı mod, elle adım | Tamam |
| 7 | Antrenman hatırlatıcısı, program uyumu, form ipuçları, ölçü karşılaştırma | Tamam |

## Derleme (Mac gerekmez)

Proje dosyası repoda tutulmaz; GitHub Actions her push'ta [XcodeGen](https://github.com/yonaskolb/XcodeGen) ile `project.yml`'den üretir, derler, testleri simülatörde çalıştırır ve imzasız bir IPA üretir.

- **IPA:** Actions → ilgili çalıştırma → *Artifacts* → `FarvaTrack-IPA`
- **Loglar:** her çalıştırmadan sonra `ci-logs` branch'ine yazılır (`STATUS.txt`, `build-errors.txt`, `test-summary.txt`, tam loglar).

Mac'te yerel derleme için: `brew install xcodegen && xcodegen generate && open FarvaTrack.xcodeproj`

## Firebase kurulumu

1. [Firebase konsolunda](https://console.firebase.google.com) bir proje oluştur.
2. iOS uygulaması ekle. **Bundle ID:** `com.farvatrack.FarvaTrack`. `GoogleService-Info.plist` dosyasını indir.
3. **Authentication → Sign-in method:** *Email/Password*'ü etkinleştir. (*Apple* girişi ücretli Apple Developer hesabı ve imzalı derleme ister.)
4. **Firestore Database** oluştur. *Rules* sekmesine `firebase/firestore.rules` içeriğini yapıştırıp yayınla. (Firebase Storage kullanılmıyor; dosyalar için aşağıdaki medya sunucusuna bak.)
5. GitHub'da **Settings → Secrets and variables → Actions → New repository secret**:
   - Ad: `GOOGLE_SERVICE_INFO_PLIST`
   - Değer: `GoogleService-Info.plist` dosyasını Not Defteri ile açıp **tüm içeriğini** yapıştır.
6. Actions'ta derlemeyi yeniden çalıştır.

Secret yoksa uygulama çökmez; "Firebase yapılandırılmadı" ekranıyla açılır.

> `GoogleService-Info.plist` repoya eklenmez (`.gitignore`'da). Güvenlik, Firebase kurallarıyla sağlanır.

### Yönetici (admin) rolü

Biyolojik atık sayacını her kullanıcı kendisi için kullanır. `role: "admin"` alanı olan hesap, sayaç ekranındaki kişiler simgesinden tüm kullanıcıların **yalnızca günlük toplamlarını** görür; kayıtların saatleri kullanıcıya özeldir ve Firestore kuralları yöneticinin bunları okumasını engeller. Rolü Firebase konsolundan verirsin: **Firestore → users → (kullanıcının uid'si) → alan ekle:** `role` (string) = `admin`. Kurallar, uygulamanın bu alanı değiştirmesine izin vermez.

> Kurallar değiştiğinde `firebase/firestore.rules` içeriğini Firebase konsolundaki **Rules** sekmesine yeniden yapıştırıp yayınla.

## Medya sunucusu (Cloudflare R2)

Fotoğraf, video, sesli mesaj, sticker, baloncuk görselleri ve profil fotoğrafı Firebase Storage yerine Cloudflare R2'de tutulur (ücretsiz kota: 10 GB depolama, indirme trafiği ücretsiz). Aradaki küçük sunucu (`cloudflare/media-worker`) her isteği Firebase oturumuyla doğrular ve eski Storage kurallarıyla aynı izinleri uygular.

**Saklama:** Alıcı cihaz gelen fotoğraf/videoların orijallerini kendiliğinden indirir (ayar açıksa Fotoğraflar'a da kaydeder) ve sunucuya "aldım" der. Sunucu her gün, alınmış orijallerden 60 günü geçenleri; toplam 9 GB'ı geçerse 60 günü doldurmamış olanları da en eskiden başlayarak buluttan siler. Önizlemeler, sesler ve sticker'lar kalır. Durum: **Ayarlar → Sohbet → Bulut depolaması**.

Kurulum (bir kez):

1. [Cloudflare](https://dash.cloudflare.com/sign-up) hesabı aç. Sol menüden **R2 Object Storage**'ı etkinleştir (ücretsiz planda da ödeme yöntemi istenebilir; kota aşılmadıkça ücret çıkmaz).
2. Sağ üst profil → **My Profile → API Tokens → Create Token** → **Edit Cloudflare Workers** şablonu. *Permissions*'a **Account → Workers R2 Storage → Edit** satırını ekle, oluştur ve belirteci kopyala.
3. Panel ana sayfasında sağdaki **Account ID**'yi kopyala.
4. GitHub → **Settings → Secrets and variables → Actions → Secrets**: `CLOUDFLARE_API_TOKEN` ve `CLOUDFLARE_ACCOUNT_ID`.
5. **Actions → Medya sunucusu (Cloudflare) → Run workflow**. Bitince özet sayfasında sunucu adresi (`https://farvatrack-media.<hesap>.workers.dev`) yazar.
6. Bu adresi **Settings → Secrets and variables → Actions → Variables** altında `MEDIA_SERVER_URL` adıyla kaydet ve derlemeyi yeniden çalıştır.

Worker kodu değişip `main`'e girince iş akışı kendiliğinden yeniden dağıtır.

## IPA'yı telefona kurma

Actions'ın ürettiği IPA ad-hoc imzalıdır (yetkiler gömülü, sertifika yok); telefona kurulurken yeniden imzalanması gerekir. Ücretsiz Apple ID ile Windows veya Mac'ten [Sideloadly](https://sideloadly.io) kullanarak kurabilirsin; ücretsiz hesapla imzalanan uygulama 7 gün çalışır ve Apple ile giriş, App Groups gibi bazı yetenekler çalışmayabilir. Kalıcı dağıtım (TestFlight) için ücretli Apple Developer Program üyeliği ve imzalama ayarı gerekir.

## TestFlight (ücretli Apple Developer hesabı gerekir)

Ücretsiz Apple ID ile yalnızca Sideloadly ile 7 günlük kurulum yapılabilir. Uygulamayı TestFlight üzerinden kalıcı dağıtmak için:

1. [Apple Developer Program](https://developer.apple.com/programs/)'a katıl (yıllık ücretli).
2. [App Store Connect](https://appstoreconnect.apple.com) → **Uygulamalar → +** ile yeni uygulama oluştur; Bundle ID: `com.farvatrack.FarvaTrack`.
3. **Kullanıcılar ve Erişim → Entegrasyonlar → App Store Connect API** bölümünden **Admin** rolüyle bir anahtar oluştur ve `.p8` dosyasını indir (yalnızca bir kez indirilebilir).
4. GitHub'da şu secret'ları ekle:
   - `APPLE_TEAM_ID`: Developer hesabındaki 10 karakterlik Team ID
   - `ASC_KEY_ID`: API anahtarının Key ID'si
   - `ASC_ISSUER_ID`: API sayfasındaki Issuer ID
   - `ASC_KEY_P8`: `.p8` dosyasının tüm içeriği
5. **Actions → TestFlight → Run workflow**. İş akışı sertifika ve profilleri otomatik oluşturur, derlemeyi imzalar ve TestFlight'a yükler. Her çalıştırmanın derleme numarası artar.

## Proje rehberi

Mimari kurallar, CI akışı ve yol haritası için `CLAUDE.md`'ye bak.

## Testler

`FarvaTrackTests` hedefi CI'da simülatörde çalışır. Yerelde: Xcode'da ⌘U.
