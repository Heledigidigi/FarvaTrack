# FarvaTrack

SwiftUI ile yazılmış fitness ve sağlık takip uygulaması (iOS 17+, MVVM, SwiftData, Firebase).

## Durum

| Aşama | İçerik | Durum |
|---|---|---|
| 1 | Giriş / kayıt (e-posta, Apple), onboarding, sekmeler, Özet ekranı | Tamam |
| 2 | Egzersiz, adım (HealthKit) ve adım widget'ı | Tamam |
| 3 | Beslenme, su, uyku, kilo | Sırada |
| 4 | Atık sayacı, istatistikler, rozetler, hatırlatıcılar | Sırada |
| 5 | Profil, ayarlar, hesap silme, imzalama | Sırada |

Henüz eklenmeyen modüller uygulamada "bir sonraki aşamada ekleniyor" ekranıyla görünür.

## Derleme (Mac gerekmez)

Proje dosyası repoda tutulmaz; GitHub Actions her push'ta [XcodeGen](https://github.com/yonaskolb/XcodeGen) ile `project.yml`'den üretir, derler, testleri simülatörde çalıştırır ve imzasız bir IPA üretir.

- **IPA:** Actions → ilgili çalıştırma → *Artifacts* → `FarvaTrack-IPA`
- **Loglar:** her çalıştırmadan sonra `ci-logs` branch'ine yazılır (`STATUS.txt`, `build-errors.txt`, `test-summary.txt`, tam loglar).

Mac'te yerel derleme için: `brew install xcodegen && xcodegen generate && open FarvaTrack.xcodeproj`

## Firebase kurulumu

1. [Firebase konsolunda](https://console.firebase.google.com) bir proje oluştur.
2. iOS uygulaması ekle. **Bundle ID:** `com.farvatrack.FarvaTrack`. `GoogleService-Info.plist` dosyasını indir.
3. **Authentication → Sign-in method:** *Email/Password*'ü etkinleştir. (*Apple* girişi ücretli Apple Developer hesabı ve imzalı derleme ister.)
4. **Firestore Database** ve **Storage** oluştur. *Rules* sekmelerine `firebase/firestore.rules` ve `firebase/storage.rules` içeriğini yapıştırıp yayınla.
5. GitHub'da **Settings → Secrets and variables → Actions → New repository secret**:
   - Ad: `GOOGLE_SERVICE_INFO_PLIST`
   - Değer: `GoogleService-Info.plist` dosyasını Not Defteri ile açıp **tüm içeriğini** yapıştır.
6. Actions'ta derlemeyi yeniden çalıştır.

Secret yoksa uygulama çökmez; "Firebase yapılandırılmadı" ekranıyla açılır.

> `GoogleService-Info.plist` repoya eklenmez (`.gitignore`'da). Güvenlik, Firebase kurallarıyla sağlanır.

### Yönetici (admin) rolü

Biyolojik atık modülü yalnızca `role: "admin"` alanı olan hesaplarda görünür. Rolü Firebase konsolundan verirsin: **Firestore → users → (kullanıcının uid'si) → alan ekle:** `role` (string) = `admin`. Kurallar, uygulamanın bu alanı değiştirmesine izin vermez.

## IPA'yı telefona kurma

Actions'ın ürettiği IPA ad-hoc imzalıdır (yetkiler gömülü, sertifika yok); telefona kurulurken yeniden imzalanması gerekir. Ücretsiz Apple ID ile Windows veya Mac'ten [Sideloadly](https://sideloadly.io) kullanarak kurabilirsin; ücretsiz hesapla imzalanan uygulama 7 gün çalışır ve Apple ile giriş, App Groups gibi bazı yetenekler çalışmayabilir. Kalıcı dağıtım (TestFlight) için ücretli Apple Developer Program üyeliği ve imzalama ayarı gerekir.

## Proje rehberi

Mimari kurallar, CI akışı ve yol haritası için `CLAUDE.md`'ye bak.

## Testler

`FarvaTrackTests` hedefi CI'da simülatörde çalışır. Yerelde: Xcode'da ⌘U.
