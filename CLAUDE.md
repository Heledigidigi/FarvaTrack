# FarvaTrack: proje rehberi

iOS 17+ fitness ve sağlık takip uygulaması. Swift 5 dil modu, SwiftUI, MVVM, `@Observable`, async/await, SwiftData (çevrimdışı), Firebase (Auth, Firestore), dosyalar için Cloudflare R2 (medya sunucusu). Arayüz metinleri ve kod yorumları **Türkçe**.

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
- Dosyalar (sohbet medyası, ses, sticker, baloncuk, profil fotoğrafı) Firebase Storage'da değil, `cloudflare/media-worker` (Cloudflare Worker + R2) üzerinden: `ChatMediaStoring` → `MediaServerClient`. Worker her isteği Firebase ID token ile doğrular; izinler `src/rules.js` (eski Storage kurallarıyla aynı; sohbet üyeliği kullanıcının belirteciyle Firestore'daki oda belgesinden). Uç noktalar `src/index.js` başında. Testler `node --test test/*.test.js` (CI'da çalışır). Dağıtım `.github/workflows/media-worker.yml` (main'de worker değişince ya da elle; secret'lar `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`). Sunucu adresi GitHub değişkeni `MEDIA_SERVER_URL` → CI `FarvaTrack/Resources/MediaServer.plist` yazar (repoda yok); yoksa `AppError.mediaServerNotConfigured`.
- Saklama: alıcı cihaz gelen foto/video orijallerini kendiliğinden indirir (`ChatViewModel.fetchPendingOriginals`, uygulamada `autoFetchOriginals: true`), kalıcı klasörde tutar (`ChatMediaFiles.originalURL`, eski önbellektekiler taşınır), ayar açıksa Fotoğraflar'a kaydeder (`ChatMediaPreferences`, `PhotoLibrarySaving`) ve `/v1/ack` ile bildirir. Worker cron'u her gün: alınmış orijallerden 60 günü geçenleri, toplam 9 GB'ı geçerse en eskiden başlayarak 8,5 GB'a inene kadar siler; önizleme/ses/sticker kalır. 404 → `AppError.mediaRemoved`. Ayarlar → Sohbet → Bulut depolaması (`ChatStorageView`).
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
| 8 | Sohbet: iki kişilik özel sohbet (alt aşamalar 8A–8H aşağıda) | 8A–8H + düzeltmeler tamam |


### Aşama 8: Sohbet (plan)

İki kişilik özel sohbet modülü (`Features/Chat`). Ücretli Apple Developer hesabı alınacakmış gibi tasarlanır: APNs, CallKit ve PushKit kodda hazır olur; hesap gelene kadar bu yetenekler kapalı/uyarılı çalışır, ücretsiz imzalı kurulumda uygulama çökmez.

**8A: Temel sohbet** (Tamamlandı)
- Uygulandığı haliyle: `Sohbet` sekmesi (sekme çubuğu 5'te kalsın diye Su, Özet'ten açılan `AppRoute.water` oldu); eşleşme `chatInvites/{kod}` (6 karakter, 24 saat, tek kullanım) ile; oda kimliği `<küçük uid>_<büyük uid>`; `ChatSyncing`/`ChatService`, `ChatViewModel`, SwiftData `ChatMessageRecord` + `ChatPendingOperation` (çevrimdışı kuyruk); tepki, düzenleme (15 dk), mesaj arama da eklendi.
- İki kullanıcı arasında tek bir sohbet odası; Firestore `chats/{chatId}/messages` ve yalnızca iki katılımcının okuyup yazabildiği kurallar.
- Metin mesajı gönderme/alma, anlık dinleyici (snapshot listener), SwiftData'da çevrimdışı önbellek ve gönderilemeyenler için kuyruk.
- Mesaj durumları: gönderiliyor, iletildi, okundu; "yazıyor…" göstergesi.
- Mesaj silme (benden/herkesten), yanıtlama (alıntı) ve kopyalama.
- Hesap silme ve veri dışa aktarmaya sohbet verisinin eklenmesi.

**8B: Medya + kamera** (Tamamlandı)
- Uygulandığı haliyle: PHPicker (`preferredAssetRepresentationMode = .current`) ve AVFoundation kamera (HEIC/HEVC); gönderirken Orijinal (varsayılan, bayt bayt kopya) / Hızlı (2048 px JPEG, 720p MP4). Storage yolu `chats/{chatId}/media/{messageId}/thumb.jpg` + `original.<uzantı>`; kurallar `firebase/storage.rules` (üyelik `firestore.get` ile), `firebase.json` ikisini de gösterir.
- Akış: `ChatMediaProcessor` önizlemeyi cihazda üretir → `.create` işlemi önce önizlemeyi yükler, sonra `media.status = uploading` ile mesajı yazar → `.uploadOriginal` işlemi sıralı kuyruğu bekletmeden `putFile` (resumable) ile orijinali yükler → `status = ready`. Aşama `ChatMessageRecord.uploadStage`'de; ağ hatasında 20 sn bekleyip ya da uygulama öne gelince kaldığı aşamadan sürer. Gönderilecek dosyalar Application Support'ta, indirilenler Caches'ta (`ChatMediaFiles`).
- Servisler: `ChatMediaStoring`/`ChatMediaStorage`, `ChatMediaProcessing`/`ChatMediaProcessor`; görüntüleyici `ChatMediaViewer` (yakınlaştırma, video, Fotoğraflar'a orijinal kaydetme).
- Fotoğraf ve videoyu kalite kaybı olmadan gönderme (orijinal dosya Firebase Storage'a; sohbette önizleme küçük resmi).
- WhatsApp benzeri anlık kamera: sohbetten tek dokunuşla foto çek / basılı tutarak video kaydet.
- Yükleme ilerlemesi, iptal ve yeniden deneme; büyük dosyalar için arka planda yükleme.
- Tam ekran görüntüleyici (yakınlaştırma, video oynatma) ve cihaza kaydetme.

**8C: Sesli mesaj** (Tamamlandı)
- Uygulandığı haliyle: `VoiceRecorder` (AVAudioRecorder, AAC .m4a, 48 kHz mono, 64 kbps) + `ChatVoiceRecorderModel` (basılı tut / sola 110 pt iptal / yukarı 90 pt kilit; 0,6 sn'den kısa kayıt atılır, 15 dk sınır). Dalga formu 48 çubuk (0…255) mesajla `audio.waveform` olarak gider.
- Gönderim: `.create` işlemi önce `chats/{chatId}/media/{messageId}/voice.m4a` dosyasını yükler, sonra mesajı yazar (alıcı hemen çalabilir). Alıcı çalınca `listenedAt` (ve `readAt`) yazılır; kurallar yalnızca alıcıya ve bir kez izin verir.
- `ChatAudioPlayer` (+ `AudioPlaybackEngine`, `AudioSessionControlling`, `ProximityMonitoring` protokolleri): 1x/1,5x/2x (tercih saklanır), sürükleyerek ilerleme; `.playback` (sessiz modda da çalar), kulağa yaklaşınca ahize, kulaklık çıkınca/kesintide duraklatma.
- Basılı tutarak kayıt, yukarı kaydırarak kilitleme, sola kaydırarak iptal.
- Kayıt sırasında ve oynatmada dalga formu; oynatma hızı (1x / 1,5x / 2x).
- Düşük gecikme için sıkıştırılmış ses (AAC) ve anında gönderim; dinlendi bilgisi.
- Mikrofon izni ve sessiz mod/kulaklık geçişleri.

**8D: Sticker oluşturucu** (Tamamlandı)
- Uygulandığı haliyle: modül `Features/Stickers`. Sohbette yazma alanındaki gülen yüz → `StickerLibraryView` (kütüphane) → fotoğraf seç → `StickerEditorView`. Gönderme ve serbest yerleştirme 8E'de.
- Arka plan `VisionStickerSegmenter` (`VNGenerateForegroundInstanceMaskRequest`, cihazda; simülatörde desteklenmez → fotoğrafın tamamıyla başlanır ve uyarı gösterilir). Çalışma görüntüsü en fazla 1024 px.
- Saf, test edilen maske mantığı `StickerMask.swift`: fırça (silgi/onar, yarıçap, yumuşaklık: sert çekirdek + smoothstep), boşluksuz çizgi, sınır kutusu, 2 geçişli chamfer mesafe alanı → kontur, `StickerGeometry` (fırça 70 pt yukarıda, ekran↔piksel dönüşümü, 512 sığdırma), `UndoStack` (30 adım).
- Tuval `StickerCanvas` (UIKit hareketleri: tek parmak fırça / "Gezin", iki parmak yakınlaştır-kaydır; ikinci parmak gelince yarım darbe iptal), büyüteç, yazı/emoji katmanları. `StickerRenderer`: maske × fotoğraf + katmanlar → kırp → 512'ye sığdır → beyaz kontur (yazılar dahil) → şeffaf PNG.
- Kütüphane: SwiftData `StickerRecord` + PNG Application Support/Stickers; `StickerLibraryViewModel` senkronu (bekleyen silmeler `PendingDeletionStore` "Sticker", yüklemeler, diğer cihazdan indirme/silme). Firestore `users/{uid}/stickers/{id}`, Storage `users/{uid}/stickers/{id}.png` (yalnızca sahibi, PNG, < 2 MB).
- Fotoğraftan otomatik arka plan kaldırma (Vision, cihaz üzerinde).
- Silgi ve onarma kalemleri; dokunduğun yerin biraz üstünde çalışan ofsetli fırça ve fırça boyutu ayarı.
- Kenar kontur (beyaz çerçeve) ve kırpma; şeffaf PNG/WebP olarak kaydetme.
- Kişisel sticker kütüphanesi, Firestore/Storage ile iki cihaz arasında senkron.

**8E: Sticker gönderme + serbest yerleştirme** (Tamamlandı)
- Uygulandığı haliyle: yazma alanındaki gülen yüz artık `ChatStickerPanel` açar (Son kullanılanlar `StickerRecents` + Kütüphanem; dokun = gönder, uzun bas = "Sohbete yerleştir"; + → `StickerLibraryView`). Sticker mesajı `type: sticker`, `sticker {path, width, height}`; PNG `chats/{chatId}/media/{messageId}/sticker.png`'ye mesajdan önce yüklenir. Alıcı uzun basıp "Kütüphaneme kaydet" (`StickerLibraryViewModel.addPNG`).
- Yerleştirme `chats/{chatId}/placements/{id}`: `senderId, anchorMessageId, x (genişliğe oran 0–1), y (bağlı mesajın dikey ortasına göre pt), scale (0,3–3; genişliğin %32'si × scale), rotation (rad), z, sticker`. Saf dönüşüm `PlacementGeometry` (en yakın mesaj, içerik ↔ bağlı konum, görünen bölgenin ortası) + `PlacementTransform` (sürükle/büyüt/döndür) testli.
- Çizim: mesaj çerçeveleri `MessageFramePreference` ile içerik koordinatında; yerleştirmeler `overlayPreferenceValue` ile içeriğe çizilir, mesajla birlikte kayar. Taslak modunda kaydırma kapalı; yalnızca yerleştiren taşır / öne-arkaya alır / siler (kurallar da). SwiftData `ChatPlacementRecord` (çevrimdışı, bekleyen yerel değişiklik kazanır).
- Test notu: arka planda süren görevler kapanmış bellek içi veritabanına erişip başka testlerde çökme yapıyordu; veritabanı kullanan test sınıflarında `tearDown` görevleri bekler. `RGBABuffer.makeImage()` veri sağlayıcıyla (paylaşılan bellek yok).
- Sticker panelinden gönderme; karşı tarafın sticker'ı kendi kütüphanesine kaydedebilmesi.
- Instagram gibi sohbet üzerinde serbest yerleştirme: büyütme, döndürme, sürükleme (iki parmak hareketleri).
- Yerleştirilen sticker'ın konumu/ölçeği/açısı mesajla birlikte saklanır, iki tarafta da aynı görünür.
- Sticker'a uzun basınca kaydet / sil / öne-arkaya al.

**8F: Sohbet baloncukları** (Tamamlandı)
- Uygulandığı haliyle: model `BubbleStyle` (Codable JSON; `sanitized()` sınırları uygular): şekil (köşe 4–28, kuyruk yok/klasik/kıvrık/düşünce), dolgu (düz/doğrusal/radyal, en çok 3 renk), kenarlık, yazı rengi, en çok 12 süsleme (emoji/yazı/sticker; 8 köşe-kenar noktasına sabitli, kaydırma ±40, boyut, açı), çizim dosyası, efekt (parıltı/ışıma/parçacık + yoğunluk), isteğe bağlı elle dilim payları. 8 hazır stil `preset.*` (Bordo Klasik, Gece, Gül Kurusu, Altın Çerçeve, Neon Bordo, Yıldızlı Gece, Pati, Minimal) cihazda çözülür.
- 9-dilim: `BubbleArtRenderer` sanatı (şekil + dolgu + çizim + iç kenarlık) referans 180×110 pt @3x bir kez çizer; `BubbleArt` 9 parçaya böler, `NineSliceArtView` Canvas ile köşeleri sabit, kenarları tek yönde, ortayı iki yönde esneterek çizer (`NineSlice` saf, testli; hedef paylardan küçükse paylar orantılı küçülür). Paylar `BubbleLayout.automaticInsets` (yarıçap + kenarlık + kuyruk) ya da elle. Süslemeler esnemez, `BubbleLayout.position` ile sabit noktalarına göre üstte çizilir. Gelen mesajda şekil aynalanır, yazı/süsleme ters dönmez. `BubbleArtCache` (64 kayıt, anahtar sahip+id+sürüm+yön).
- Efektler `BubbleEffects.metal` (`[[stitchable]]` bubbleShimmer/bubbleSparkle colorEffect, bubbleGlow layerEffect) + `TimelineView(.animation)`; `BubbleEffectPolicy`: Hareketi azalt açıksa kapalı. Yalnızca metin ve sesli mesajlar baloncuk taşır (medya/sticker hariç).
- Editör: sohbet araç çubuğundaki palet → `BubblePickerView` (Varsayılan, hazırlar, Benim baloncuklarım; kopyasını düzenle/düzenle/sil) → `BubbleEditorView` (kısa/uzun/gelen canlı önizleme, şekil, dolgu, kenarlık, süslemeler, PencilKit `BubbleDrawingSheet`, efekt, dilim kılavuzu + elle ayar).
- Senkron: `BubbleStyleStore` (+ `BubbleSyncing`/`BubbleService`), SwiftData `BubbleStyleRecord` (kendi stillerim + karşı tarafın önbelleği), dosyalar `BubbleFiles` (kendi: Application Support/Bubbles, diğer: Caches/Bubbles). Firestore `users/{uid}/bubbles/{id}` `{json, version, updatedAt}`; Storage `users/{uid}/bubbles/{styleId}/{assetId}.png` (PNG < 1 MB). Okuma: sahibi ya da onunla sohbeti olan (`sharesChatWith`). Mesajda `bubble {id, version}`; karşı cihaz stil yoksa ya da sürüm daha yeniyse indirip önbelleğe alır. Düzenleme sürümü artırır; silme `PendingDeletionStore` "Bubble". Seçim `chat.bubble.selected.<uid>`.
- Test notu: sahte servislerin yalıtımsız async metotları genel yürütücüde eşzamanlı çalışır; kayıt dizilerine yazım `mockLock.withLock` ile yapılır (yoksa yığın bozulması).
- Hazır baloncuk temaları ve kullanıcının kendi tasarladığı özel baloncuklar.
- Baloncuk düzenleyici: çizim, sticker, yazı, emoji ve efekt ekleme.
- Dokuz dilimli (9-slice) ölçekleme: mesaj uzayıp kısaldıkça baloncuğun şekli bozulmaz.
- Seçilen özel baloncuk karşı tarafa da aynen görünür (tasarım verisi mesajla/kullanıcı profiliyle senkron).

**Kendine not sohbeti** (8F sonrası ek, tamamlandı)
- Kullanıcı kendi davet kodunu kendine yapıştırınca `uid_uid` odası açılır (`members: [uid, uid]`); karşılıklı sohbetle aynı altyapı ve özellikler, yalnızca alıcı yine kendisi. `ChatRoomKind` (`.partner`/`.personal`, `ChatRoomKind.of(room, userID:)`), `ChatViewModel(kind:)`; `observeRoom(userID:kind:)` kullanıcının odalarını dinleyip türe göre seçer. `ChatRoomCache` anahtarı türe göre (karşılıklı eski anahtarla). Bekleyen işlemler (`pendingOperations`) odaya göre ayrılır.
- `ChatHub` (MainTabView): iki model, rozet toplamı, görünürlük (yalnızca açık konuşma okundu sayar). Sohbet sekmesi: not sohbeti yoksa eskisi gibi doğrudan karşılıklı sohbet / eşleşme (sol üst menü → "Kendime not sohbeti aç"), varsa `ChatRoomListView` (iki satır) → `ChatRoomContent`. Eşleşme ekranı `ChatPairingView(purpose:)`, "Panodan yapıştır" düğmesi.
- Not sohbetinde "yazıyor" gönderilmez; orijal yüklenince kendi `/v1/ack`'i atılır (Worker `uid_uid` odasında gönderene izin verir), bulut temizliği uygulanır. Firestore kuralları: kodun sahibi de kullanabilir; oda `members[0] < members[1]` ya da iki üye de kendisi.

**8G: Push bildirimleri** (Tamamlandı)
- Uygulandığı haliyle: Cloud Functions yerine (Blaze gerektirmesin diye) bildirimi medya sunucusu gönderir. Mesaj Firestore'a yazılınca (`ChatViewModel` kuyruğu `.create` başarılı → `notifyRecipient`) uygulama `POST /v1/notify {chatId, messageId}` çağırır (`ChatNotifying`, `MediaServerClient`; ağ hatasında bir kez daha). Worker (`src/google.js` servis hesabı OAuth JWT + Firestore REST, `src/push.js` saf içerik): istekte bulunanın odanın üyesi ve mesajın göndereni olduğunu doğrular, karşı tarafın `users/{uid}/devices` kayıtlarından sessize alınmamışlara FCM HTTP v1 ile gönderir (başlık gönderenin adı; metin türe göre "📷 Fotoğraf", "🎤 Sesli mesaj"…; rozet = son 50 mesajda okunmamış; `category: CHAT_MESSAGE`, `thread-id: chatId`, `data.kind = chat`), geçersiz belirteci siler, aynı mesajı 10 dk içinde ikinci kez göndermez. Not sohbetinde bildirim yok. Secret `FIREBASE_SERVICE_ACCOUNT` (yoksa sessizce atlanır).
- Uygulama: `PushManager` (+ `PushSystem`, `PushDeviceStoring` protokolleri): oturum açılınca izin + APNs kaydı, FCM belirteci `users/{uid}/devices/{cihazId}` (`token, platform, muted, appVersion, updatedAt`); oturum kapanınca kayıt ve FCM belirteci silinir. `AppDelegate`: `MessagingDelegate`, APNs belirteci, kayıt hatası → `.unavailable` (ücretsiz imza). Push yetkisi `PUSH_NOTIFICATIONS` build ayarıyla (`Config/FarvaTrack-push-NO/YES.entitlements`; varsayılan NO, TestFlight `vars.PUSH_NOTIFICATIONS || YES`); sideload IPA kendi entitlements dosyasını kullanır.
- Bildirim eylemleri `ChatNotificationAction` (Yanıtla metin girişli, Okundu işaretle) → `ChatQuickActions` (uygulamayı açmadan doğrudan `ChatSyncing` ile yazar, yanıtta okundu da işaretler). Dokununca `PushManager.pendingChatID` → `ChatHub.open` → ilgili sohbet.
- Uygulama açıkken sohbet push'u gösterilmez (`willPresent` → []); yerine anlık dinleyiciden gelen yeni mesaj (`ChatViewModel.onIncoming`, son 2 dk, önbellekte olmayan) `ChatHub.banner` → `ChatBannerView` şeridi (4 sn, dokun = aç, yukarı kaydır = kapat); açık konuşmada ve arka planda şerit yok. Uygulama simgesi rozeti `ChatHub.unreadCount` (`setBadgeCount`). Ayarlar → Sohbet → "Sohbet bildirimleri" (cihaz bazında sessize alma) ve durum metni.
- APNs kaydı ve cihaz belirtecinin Firestore'a yazılması; Cloud Functions ile yeni mesajda bildirim gönderimi.
- Bildirimde yanıtlama ve okundu işaretleme (bildirim eylemleri); sessize alma ayarı.
- Rozet sayısı ve uygulama açıkken bildirim yerine uygulama içi gösterim.
- Ücretsiz imzada APNs yokken düzgün geri düşme (yalnızca uygulama açıkken anlık dinleyici).

**8H: Sesli arama** (Tamamlandı)
- Uygulandığı haliyle: modül `Features/Calls`. WebRTC `stasel/WebRTC` (SPM, `branch: latest`); `CallMediaEngine` protokolü, canlı `WebRTCEngine` (yalnızca ses, unified plan, `gatherContinually`, AEC/NS/AGC/HPF kısıtları, `RTCAudioSession.useManualAudio` → ses CallKit etkinleştirince açılır), paket yoksa `UnavailableCallEngine`. SDP `CallAudioTuning.tune`: Opus en önde, `maxaveragebitrate=64000; useinbandfec=1; usedtx=0; stereo=0; minptime=10` (saf, testli).
- Sinyalleşme `CallSignaling`/`CallSignalingService`: `chats/{chatId}/calls/{callId}` `{callerId, calleeId, status (ringing/accepted/declined/busy/missed/ended/failed), offer, answer, offerVersion, answerVersion, createdAt, answeredAt, endedAt, endedBy}` + `candidates/{id}` `{from, candidate, sdpMid, sdpMLineIndex, offerVersion}`. Kurallar: arayan oluşturur ve teklif yazar, aranan yanıt yazar, ikisi durumu ilerletir.
- `CallManager` (`@MainActor @Observable`, `.shared`; tüm bağımlılıklar enjekte, testli): `CallPhase` + saf `CallStateMachine`; giden (CallKit start → TURN `/v1/turn` → teklif → belge → `/v1/call` çaldırma), gelen (`watch(chatID:)` ile çalan aramalar dinlenir; uygulama açıkken CallKit'e bildirilir; başka arama sürerken `busy`), 45 sn çalma → cevapsız, bağlanma 30 sn; uzak adaylar yanıt uygulanana kadar bekletilir. Yeniden bağlanma: ICE `disconnected` 2 sn sürerse, `failed` ya da ağ değişince (`NWPathMonitor`) arayan `offerVersion`'ı artırıp ICE restart teklifi yazar, aranan yeni teklife yanıt verir; 30 sn'de düzelmezse biter; süre sıfırlanmaz. Kalite: 2 sn'de bir `getStats` → `CallStatsParser` → `CallQuality` (RTT/kayıp/titreşim, 3 çubuk; TURN aktarımı gösterilir).
- CallKit `CallKitSystem` (`CallSystemUI`): sistem ekranı, sessiz, beklet; uygulama içi düğmeler CXTransaction ile; hoparlör `overrideOutputAudioPort`, Bluetooth `allowBluetooth`. PushKit `VoIPPushRegistrar`: `VOIP_PUSH` build ayarı (Info.plist `FTVoIPPushEnabled`; varsayılan NO, TestFlight `vars.VOIP_PUSH || YES`) YES ise kaydolur, VoIP belirteci `devices.voipToken`; her VoIP push'ta hemen CallKit'e bildirilir (`handleVoIPPush`, arama bitmişse cevapsız olarak kapatılır). `UIBackgroundModes`: audio, voip, remote-notification.
- Sohbette arama satırı: arama bitince yalnızca arayan `call-{callId}` kimlikli `type: call` mesajı yazar, `call {callId, outcome: answered/missed/declined/busy/failed, duration}` (`ChatCallInfo`, `CallFormat.summary`: "📞 Sesli arama · 2:34", "📞 Cevapsız arama"…); baloncukta yön simgesi ve "Geri ara"; bildirimi de 8G yoluyla. Arama düğmesi sohbet araç çubuğunda (yalnızca karşılıklı sohbet), mikrofon izni önce sorulur. Arama ekranı `CallView` (`MainTabView` fullScreenCover).
- Worker: `/v1/turn` (`src/turn.js`: Cloudflare Realtime TURN `TURN_KEY_ID` + `TURN_KEY_API_TOKEN` → kısa ömürlü kimlik, 53. port ayıklanır; yoksa `TURN_URLS`/`TURN_USERNAME`/`TURN_CREDENTIAL`; yoksa yalnızca STUN), `/v1/call` (`src/apns.js`: `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` ile ES256 JWT, `apns-push-type: voip`, üretim → `BadDeviceToken` ise sandbox; VoIP yoksa FCM "📞 Seni arıyor", `data.kind = call`).
- Yüksek kaliteli, düşük gecikmeli sesli arama (WebRTC; sinyalleşme Firestore üzerinden, gerekirse TURN sunucusu).
- CallKit ile sistem arama ekranı; PushKit VoIP bildirimiyle kilitliyken gelen arama.
- Hoparlör, sessiz, Bluetooth kulaklık geçişleri; arama süresi ve kalite göstergesi.
- Cevapsız arama kaydı ve sohbette arama geçmişi satırı.

**Sohbet düzeltmeleri** (8H sonrası, tamamlandı)
- Sohbet sekmesi hep `ChatRoomListView` ile açılır (Karşılıklı + "Kendime not"; not sohbeti yoksa satır kurulum açar). Açık konuşmada ve sticker panelinde sekme çubuğu gizli (`.toolbar(.hidden, for: .tabBar)`).
- Medya kalitesi her gönderimde sorulmaz: varsayılan Orijinal, Ayarlar → Sohbet → "Veri tasarrufu" (`ChatMediaPreferences.dataSaverKey`, `sendQuality`) açıksa Hızlı. Galeriden seçilenler doğrudan gider (`ChatMediaSendSheet` kaldırıldı).
- Kamera sonrası `ChatPhotoEditorView`: kırp (tahribatsız, `PhotoEditDocument.crop`), sticker (kütüphaneden), yazı (renkli), kalem + çizgi silgisi + geri al, Fotoğraflar'a kaydet, gönder; katmanlar sürükle/büyüt/döndür, alttaki çöpe sürükleyince silinir. Saf mantık `PhotoEdit.swift` (`PhotoEditGeometry`: dönüşümler, kırpma tutamaçları, silgi isabeti), testli. Düzenleme yoksa orijinal dosya bayt bayt gider; varsa `ImageRenderer` ile orijinal çözünürlükte HEIC. Videoda ✕ / kaydet / gönder. Kapat/vazgeç sol üstte küçük ✕; önizleme katmanı `allowsHitTesting(false)` (dönüşte ✕ basılamama hatası).
- Sticker yerleştirme: panelde dokun = gönder; basılı tutup sohbete sürükle (`.draggable` `StickerDragPayload` → içerikte `dropDestination`, nokta içerik koordinatında) → bırakılan yerde taslak, ✕ / ✓. Yatay oran içerik genişliğine göre (`ChatScrollMetrics.contentWidth`). VoiceOver eylemi son mesajın yanına yerleştirir.

**Kişi profili + hataya dayanıklı arama** (tamamlandı)
- Sohbet başlığı (avatar + ad + "bilgi için dokun") → `ChatContactProfileView`: büyük avatar, "Sesli ara" (yalnızca karşılıklı) ve "Ara" düğmeleri, medya şeridi, "Medya ve bağlantılar" (`ChatSharedContentView`: 3 sütun ızgara + bağlantı listesi; uzun bas "Sohbette göster"), Görünüm → Sohbet baloncuğu. Araç çubuğunda yalnızca arama (telefon) düğmesi; palet profile taşındı. Konuşmadaki `.searchable` kaldırıldı, arama profilde `ChatMessageSearchView`.
- `ChatViewModel.sharedMedia()` / `sharedLinks()` tüm önbellekten (ekrandaki pencereden bağımsız); bağlantılar `ChatText.links` (NSDataDetector, yalnızca http/https). Seçilen mesaj `pendingJumpMessageID` → profil kapanır, konuşma kayıp vurgular.
- Arama `ChatText.fuzzyScore`: Türkçe katlama, her sorgu kelimesi bir kelimede geçmeli ya da Damerau–Levenshtein sınırında (4–5 harf 1, 6–8 harf 2, 9+ harf 3; 3 harf ve altı birebir), yarım yazılan kelime için önek karşılaştırması; sonuçlar puan sonra tarih sırasıyla (en çok 200).
- Sticker hareketleri tüm alanda: sohbette taslak varken `PlacementGestureLayer` görünen alanın tamamını kaplar (sürükle / iki parmak büyüt-döndür; çizim `PlacementDraftView` + `PlacementLiveGesture`). Fotoğraf düzenleyicide hareket başladığı yerdeki katmana (`PhotoEditGeometry.layerHit`), yoksa seçili katmana uygulanır; dokunma seçer, seçili yazıya dokunma düzenler.

**Profil fotoğrafı, çevrimiçi, bul çubuğu, medya görüntüleyici, klavye panelleri** (tamamlandı)
- Profil fotoğrafı: seçimden sonra `ProfilePhotoCropView` ("Taşı ve Ölçekle": kaydır, iki parmakla büyüt, iki kez dokun; daire dışı karartılır). Saf geometri `AvatarCropGeometry` (taban ölçek = daireyi dolduran, kaydırma sınırı, kırpma bölgesi, parmak noktasına göre büyütme), çizim `ProfilePhotoRenderer` (640 px JPEG). Eski `ImageCompressor` kaldırıldı.
- Sohbette fotoğraflar: profiller birbirine kapalı olduğu için her üye kendi fotoğraf adresini oda belgesine yazar (`chats/{id}.photos.{uid}`, `ChatViewModel.syncMyPhoto`, yalnızca değişince). `AvatarView` bellekte önbellekli (`AvatarImageCache`); başlık, liste ve profilde `PresenceAvatarView`.
- Çevrimiçi / son görülme: `chats/{id}.presence.{uid} = {online, at}`. `ChatHub` uygulama öndeyken dakikada bir `online: true` yazar, arka plana geçince (kısa arka plan süresiyle) `online: false`. Sinyal 150 sn'den eskiyse çevrimdışı sayılır (`ChatPresence`, `ChatPresenceStatus`: "çevrimiçi" yeşil, "son görülme bugün 14:32 / dün / 12 Kas" gri). Başlıkta adın altında (`ChatPresenceSubtitle`), avatarda yeşil/gri nokta. Kurallar: her üye yalnızca kendi `photos`/`presence` anahtarını değiştirir.
- İletildi bilgisi: alıcı gelen mesajı görünce `deliveredAt` yazar (bir kez; kural yalnızca alıcıya). Uzun bas → "Bilgi" (`ChatMessageInfoSheet`, `ChatMessageInfo`): gönderildi / iletildi / görüldü (+ sesli mesajda dinlendi). Eski mesajda `deliveredAt` yoksa okunma zamanı kullanılır.
- Saat baloncukta yazmaz: sohbet sola kaydırılınca (Instagram gibi) tüm baloncuklar kayar, sağda saatler belirir (`ChatHorizontalPanAttacher` sohbetin UIScrollView'una yalnızca belirgin sola harekette başlayan bir pan ekler; `ChatTimeReveal`). Durum simgesi ve "düzenlendi" baloncukta kalır.
- Bul (Ctrl+F): profildeki "Ara" profili kapatır, konuşmada yazma alanının yerine `ChatFindBar` açılır; ölçüt `ChatText.fuzzyScore` (profildeki eski aramayla aynı), eşleşmeler eskiden yeniye (`ChatFindState`), en yenisiyle başlar; ↑ daha eski, ↓ daha yeni; seçili baloncuk vurgulu ve ortalanır. Profildeki ayrı arama sayfası (`ChatMessageSearchView`) kaldırıldı.
- Fotoğraf/video baloncuksuz ve kenarlıksız; durum simgesi fotoğrafın köşesinde küçük kapsülde. `ChatMediaViewer`: sohbetteki tüm medya arasında sağa-sola kaydırma (TabView sayfa), yakınlaştırılmamışken dikey çekince kapanır (`ZoomableImage` içindeki pan; videoda SwiftUI sürükleme), tek dokunuş çubukları gizler; tarih/boyut yok; altta Paylaş, İndir (Fotoğraflar), Düzenle → `ChatPhotoEditorView` (kırp, çiz, yazı, sticker) → indir ya da sohbete yeni mesaj olarak gönder (`ChatEditedImage`).
- Klavye yüksekliğinde paneller (`ChatInputPanels.swift`): sticker ve galeri paneli klavyenin yerini alır, animasyonsuz. Yazma alanının altındaki boşluk `ChatPanelLayout.spacer = max(0, klavye − o anki alt güvenli alan)` ve aynı yerleşim adımında hesaplanır (kök `GeometryReader`), böylece klavye inerken/çıkarken yazma alanı kıpırdamaz; panel kökte, ekranın altından klavye yüksekliğinde çizilir (`ignoresSafeArea(.keyboard)`), klavye tamamen açılınca (`keyboardDidShow`) kaldırılır. Klavye yüksekliği `ChatKeyboardObserver` ile öğrenilip saklanır (varsayılan 336). Açık panelin düğmesi klavye simgesine döner. Galeri (`ChatGalleryPanel`, PhotoKit, `NSPhotoLibraryUsageDescription`): son 600 öğe, ilk hücre kamera, en çok 10 seçim, orijinal dosya (`PHAssetResource`, HEIC/HEVC korunur); üstteki tutamaçtan yukarı çekince büyür, aşağı çekince kapanır; izin yoksa sistem seçicisi ("Albümler").
- Geri düğmesi yalnızca ok (`.toolbarRole(.editor)`).

**Düzenleyici, kaydırarak yanıt, açıklama, klavye kılavuzu** (tamamlandı)
- Fotoğraf düzenleyici (`ChatPhotoEditorView`, baştan yazıldı): kırpma sabit koordinat alanında (`photoCrop`) ölçülür → titreme yok; L köşeler + kenar tutamaçları (`CropHandle.top/bottom/left/right`), kılavuzlar yalnızca sürüklerken. Katman hareketleri UIKit `PhotoEditTransformSurface` (pan 1–2 parmak + pinch + rotation aynı anda, artımlı; parmak sayısı değişince öteleme sıçramaz; `PhotoEditLayer.applying`). Seçim çizgileri (kesikli) her yerden kaldırıldı (düzenleyici, sticker editörü, sohbette yerleştirme taslağı). Üst çubukta solda ✕ + İndir.
- Kalem modu: araç çubuğunda Kalem / Keçeli / Fosforlu / Neon (`PhotoEditBrush`) ve Silgi; renk düğmesi → palet (`PhotoEditColor.palette`), sistem renk seçici ve "Fotoğraftan seç" damlalığı (ekrandaki bileşik görüntü `ImageRenderer` → `PhotoEditPixelSampler`; parmağın 72 pt üstünden okur, sürüklerken önizler, bırakınca seçer); ayarlar → Boyut (2–40) ve Ofset (0–100 pt, `PhotoEditBrushSettings`, `@AppStorage photoEdit.brushSize/brushOffset`). Silgi artık kalem gibi: `isEraser` çizgisi `.clear` karışımıyla yalnızca çizim katmanından siler. Çizgiler orta noktalı eğrilerle yumuşatılır (`PhotoEditStrokeRenderer`).
- Açıklama: düzenleyicinin altında "Açıklama ekle…" → `onSend(image, caption)`; `sendMedia(..., caption:)` ilk öğenin `text` alanına yazar; baloncukta fotoğrafın altında küçük baloncuk; özetler `ChatText.summary` ("📷 açıklama").
- Görüntüleyici: Paylaş / İndir / Düzenle sağ üstte; altta "Yanıtla…" çubuğu (`ChatViewModel.sendReply(_:to:)`, taslağa dokunmaz), gönderince sohbete dönülür.
- Kaydırarak yanıtlama: kendi baloncuğunu sola, karşı tarafınkini sağa çek (`ChatSwipeReply`, eşik 56 pt, titreşim); baloncuk çerçeveleri `ChatBubbleFramePreference`; boş alanda sola çekmek saatleri gösterir. `ChatHorizontalPanAttacher` konumu görünen alana göre verir, içerik koordinatına `ChatScrollMetrics.contentMinY` ile çevrilir.
- Klavye ↔ panel: SwiftUI klavye kaçınması kapalı (`ignoresSafeArea(.keyboard)` + alt kenar); yazma alanının altı `ChatPanelLayout.lift = max(klavye, panel ? K : 0, ev çubuğu)`. Klavyenin gerçek konumu `ChatKeyboardTracker` (pencerenin `keyboardLayoutGuide`'ına bağlı görünmez ölçer; parmakla kapatırken de her kare) ile alınır; sistem animasyonlu değişimler klavye eğrisine yakın yayla (`ChatPanelLayout.keyboardAnimation`). Önceki sürümde `GeometryReader` alt güvenli alanı yazma alanının oturduğu alandan farklı ölçtüğü için panel yazma alanının üstüne biniyordu. Pencerenin (`UIWindow`) `keyboardLayoutGuide`'ı hiç güncellenmediği için açılma/kapanma artık klavye bildirimlerinden (`keyboardWillChangeFrame`/`WillHide`, pencere koordinatına çevrilmiş), parmakla kapatma ise kök görünüm denetleyicisinin görünümüne bağlı ölçerden alınır.
- Kaydırarak yanıt hit-testi pencere (`.global`) koordinatında: UIKit hareket konumu ile SwiftUI çerçeveleri birebir; yanıt için çekerken liste dikeyde kilitlenir; eşikte ok simgesi sıçrar.
- Yanıtta görsel: yazma alanının yanıt çubuğunda ve baloncuktaki alıntıda fotoğraf/video/sticker küçük resmi gösterilir, "Fotoğraf" yazmaz (`ChatReplyVisual`, `ChatViewModel.replyThumbnail(for:)`).
- Görüntüleyicinin yanıt çubuğu: yazı yerinde gönderilir; galeri / sticker / kamera / mikrofon görüntüleyiciyi kapatıp sohbette o fotoğrafa alıntılı olarak ilgili işlemi açar (`ChatViewerReplyAction`).
- Düzenleyicide kalem/kırpma kipinde fotoğrafın sağa-aşağı kayması giderildi (tuval alanı her kipte tam boy).

**Kutu Kedi baloncuğu** (tamamlandı)
- Hazır baloncuk `preset.kutuKedi` ("Kutu Kedi"): `BubbleStyle.art = .catBox` (isteğe bağlı alan; eski JSON'da yok → `nil`). Kafa ve patiler kullanıcının nakış fotoğrafından vektörleştirildi (`CatBoxArtData`: SVG yolları, 1600×581 px uzayı, patiler yatayda %68), gövde yumuşak köşeli kutu. 9-dilim kullanılmaz: `CatBoxBubbleView` (Canvas) `CatBoxGeometry.layout(for: boyut)` ile kutunun üst/sağ kenarını hesaplar; içerik genişledikçe sağa, uzadıkça yukarı büyür, kafa/patiler sabit. Dolgu `KumasDoku` (fotoğraftaki kumaştan, kesintisiz döşenen krem doku), çizgi #2A2320. İç boşluk ve en küçük içerik `BubbleLayout.contentPadding` / `minimumContentSize`. Yalnızca metin mesajlarında (ses/arama satırı varsayılan görünümde); açık zeminde saat, alıntı ve okundu işareti koyu/bordo. Seçicide küçültülmüş önizleme, düzenleyicide kopyalanamaz. `SVGPathParser` (M/L/Q/C/Z) ve geometri testli (`CatBoxBubbleTests`).

**Toplu düzeltmeler (2026-11-23)** (tamamlandı)
- Kutu Kedi: durum tiki baloncuğun dışında (`CatBoxStatusMark`: arkasız düz tik; iletildi #9A8877, okundu çift `ftWater`, gönderiliyor saat), merkezi `CatBoxGeometry.statusMarkOffset` ile arka bacak ile karın çizgisinin köşesinde, karın çizgisinin üstünde (yarısı kedinin içinde). İçerik kutunun üstünden ve karından eşit uzakta (`verticalInset` 55 px) → metin dikeyde ortada. "düzenlendi" metnin altında.
- Klavye: yazma alanının altındaki boşluğun alt kenarı pencerenin altına oturmuyorsa (devralınan güvenli alan payı) aradaki pay ölçülür (`ChatPanelLayout.bottomGap`) ve `lift`'ten düşülür (`visibleLift`).
- Sohbet başlığı (avatar + ad + çevrimiçi) `topBarLeading`'de, geri okunun yanında; ortadaki başlık boş tutulur (`navigationTitle` geri düğmesi için kalır).
- Medya ve bağlantılar ızgarası: `ChatSharedMediaCell` kendi kendine kare (`aspectRatio(1, .fit)` + fotoğraf `overlay` + `clipped`), taşma yok.
- `widget-yanlis-dokunus` dalı birleştirildi (dokunma alanı yalnızca damla/halka/kedi, su widget'ında 5 dk "Geri al").
- Çalışma kuralı: başka sohbetlerde de geliştiriliyor; yeni işe başlamadan ve `main`'e birleştirmeden önce `main`'de olmayan dalları kontrol et (`git fetch` + `git rev-list --count origin/main..origin/<dal>`), açıkta iş varsa önce birleştir.

Yeni modül eklerken: `AppRoute` (Özet'ten açılan sayfa) veya `AppTab`, SwiftData şeması (`FarvaTrackApp`), `LiveDashboardDataSource`, Firestore kuralları, `Constants.Collection.userSubcollections` (hesap silme), `LocalDataCleaner` ve `DataExporter` güncellenir.
