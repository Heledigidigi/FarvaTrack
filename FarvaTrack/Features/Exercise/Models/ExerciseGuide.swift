import Foundation

/// Bir egzersizin doğru yapılışına dair kısa rehber. Genel bilgilendirme amaçlıdır.
struct ExerciseGuide: Equatable {
    let symbol: String
    let muscles: [String]
    let steps: [String]
    let mistakes: [String]
    let tip: String?

    /// YouTube'da "<ad> nasıl yapılır" araması (içerik gömülmez, yalnızca bağlantı).
    static func videoSearchURL(for name: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: "\(name) nasıl yapılır doğru form")]
        return components?.url
    }
}

enum ExerciseGuides {
    static func guide(for key: String) -> ExerciseGuide? {
        guard key.hasPrefix("preset.") else { return nil }
        return all[String(key.dropFirst("preset.".count))]
    }

    private static let all: [String: ExerciseGuide] = [
        "bench-press": ExerciseGuide(
            symbol: "figure.strengthtraining.traditional",
            muscles: ["Göğüs", "Ön omuz", "Arka kol"],
            steps: [
                "Sehpaya uzan; gözlerin barın hizasında, ayakların yere tam bassın.",
                "Kürek kemiklerini geriye ve aşağı sıkıştır, sırtında hafif doğal bir kavis kalsın.",
                "Barı omuz genişliğinden biraz geniş tut, bilekler dik dursun.",
                "Barı kontrollü şekilde göğsün alt kısmına indir; dirsekler gövdeyle yaklaşık 45–70° açı yapsın.",
                "Ayaklarından güç alarak barı yukarı ve hafif geriye, omuz hizasına doğru it."
            ],
            mistakes: ["Kalçayı sehpadan kaldırmak", "Barı göğüste sektirmek", "Dirsekleri tamamen yana açmak", "Bilekleri geriye bükmek"],
            tip: "Ağır setlerde mutlaka bir yardımcı (spotter) ya da güvenlik barı kullan."
        ),
        "incline-dumbbell-press": ExerciseGuide(
            symbol: "figure.strengthtraining.traditional",
            muscles: ["Üst göğüs", "Ön omuz", "Arka kol"],
            steps: [
                "Sehpayı 30–45° eğime ayarla, dambılları uyluklarının üzerinden kaldırarak uzan.",
                "Dambılları göğüs hizasında tut, avuçlar ileriye ya da hafif içe baksın.",
                "Kontrollü şekilde yukarı it; tepede dambılları birbirine çarptırma.",
                "Göğsünde hafif bir esneme hissedene kadar yavaşça indir."
            ],
            mistakes: ["Sehpayı fazla dikleştirmek (yük omuza kayar)", "Hareketi yarım yapmak", "İnişte yükü bırakmak"],
            tip: nil
        ),
        "squat": ExerciseGuide(
            symbol: "figure.strengthtraining.functional",
            muscles: ["Ön bacak", "Kalça", "Arka bacak", "Gövde"],
            steps: [
                "Barı üst sırtına (trapezin üstüne) yerleştir, ayakları omuz genişliğinde ve uçları hafif dışa açık tut.",
                "Derin nefes al, karnını sık ve göğsünü dik tut.",
                "Kalçayı geriye, dizleri ayak uçları yönünde dışa iterek çömel.",
                "Uyluklar en az yere paralel olana kadar in; topukların yerde kalsın.",
                "Topuk ve orta ayaktan iterek kalkarken sırtının açısını koru."
            ],
            mistakes: ["Dizlerin içe çökmesi", "Topukların kalkması", "Belin yuvarlanması", "Kalkarken kalçanın önce yükselmesi"],
            tip: "Derinliği esneklik izin verdiği ölçüde artır; ağırlık yerine formu önceliklendir."
        ),
        "deadlift": ExerciseGuide(
            symbol: "figure.strengthtraining.traditional",
            muscles: ["Arka bacak", "Kalça", "Bel", "Sırt", "Ön kol"],
            steps: [
                "Ayakları kalça genişliğinde aç, bar orta ayağının üzerinde dursun.",
                "Kalçayı geriye vererek eğil, barı bacaklarının hemen dışından tut.",
                "Kürek kemiklerini sık, sırtını düz tut ve barın 'boşluğunu' al (gergin hale getir).",
                "Ayaklarınla yeri iterek kalk; bar bacaklarına yakın kalsın.",
                "Tepede kalça ve dizleri birlikte kilitle, geriye yaslanma. İnişte aynı yolu izle."
            ],
            mistakes: ["Sırtı yuvarlamak", "Barı vücuttan uzaklaştırmak", "Barı kollarla çekmeye çalışmak", "Tepede aşırı geriye yaslanmak"],
            tip: "Her tekrarda pozisyonu yeniden kur; tekrarları aceleye getirme."
        ),
        "overhead-press": ExerciseGuide(
            symbol: "figure.strengthtraining.traditional",
            muscles: ["Omuz", "Arka kol", "Üst göğüs", "Gövde"],
            steps: [
                "Ayakta, barı köprücük kemiği hizasında omuz genişliğinde tut.",
                "Kalça ve karnını sık; gövde tek parça gibi dursun.",
                "Barı düz bir çizgide yukarı it, geçerken başını hafif geriye çek.",
                "Tepede bar başının hemen üstünde olsun, kolların tam açılsın.",
                "Kontrollü şekilde başlangıca indir."
            ],
            mistakes: ["Belden aşırı geriye kavis yapmak", "Bacaklarla itme (yaylanma)", "Barı önde bitirmek"],
            tip: nil
        ),
        "barbell-row": ExerciseGuide(
            symbol: "figure.strengthtraining.traditional",
            muscles: ["Orta sırt", "Kanatlar", "Arka omuz", "Ön kol"],
            steps: [
                "Barı tut, dizleri hafif kır ve gövdeyi düz sırtla yaklaşık 45°'ye kadar öne eğ.",
                "Barı karnının üst kısmına doğru çek, dirsekler gövdeye yakın geriye gitsin.",
                "Tepede kürek kemiklerini birbirine yaklaştır.",
                "Kontrollü şekilde kollar tamamen açılana kadar indir."
            ],
            mistakes: ["Gövdeyi her tekrarda kaldırıp savurmak", "Sırtı yuvarlamak", "Hareketi kollarla bitirmek"],
            tip: nil
        ),
        "lat-pulldown": ExerciseGuide(
            symbol: "figure.strengthtraining.traditional",
            muscles: ["Kanatlar", "Arka omuz", "Ön kol"],
            steps: [
                "Uyluklarını desteğin altına sabitle, barı omuzdan geniş tut.",
                "Göğsünü dik tutup hafif geriye yaslan.",
                "Barı dirsekleri aşağı ve geriye götürerek üst göğsüne çek.",
                "Kolların tamamen uzayana kadar kontrollü bırak."
            ],
            mistakes: ["Barı ensenin arkasına çekmek", "Gövdeyi fazla geriye atıp savurmak", "Yarım hareket"],
            tip: nil
        ),
        "pull-up": ExerciseGuide(
            symbol: "figure.strengthtraining.traditional",
            muscles: ["Kanatlar", "Pazu", "Orta sırt"],
            steps: [
                "Barı omuzdan biraz geniş, avuçlar ileri bakacak şekilde tut ve asıl.",
                "Omuzlarını kulaklarından uzaklaştırarak hareketi başlat.",
                "Çeneni barın üstüne çıkarana kadar dirsekleri aşağı çekerek yüksel.",
                "Kolların tamamen açılana kadar kontrollü in."
            ],
            mistakes: ["Bacaklarla sallanarak çıkmak", "Yarım tekrar", "Omuzları kulağa doğru kaldırmak"],
            tip: "Yapamıyorsan lastik bant destekli barfiks veya negatif (yavaş iniş) ile başla."
        ),
        "push-up": ExerciseGuide(
            symbol: "figure.strengthtraining.functional",
            muscles: ["Göğüs", "Arka kol", "Ön omuz", "Gövde"],
            steps: [
                "Eller omuz genişliğinden biraz geniş, vücut baştan topuğa düz bir çizgi olsun.",
                "Karın ve kalçayı sık.",
                "Dirsekler gövdeyle yaklaşık 45° açı yaparak göğsünü yere yaklaştır.",
                "Vücudu tek parça halinde yukarı it."
            ],
            mistakes: ["Kalçanın düşmesi veya havada kalması", "Başı öne uzatmak", "Yarım hareket"],
            tip: "Zor geliyorsa elleri bir sehpaya koyarak eğimli şınavla başla."
        ),
        "biceps-curl": ExerciseGuide(
            symbol: "figure.strengthtraining.traditional",
            muscles: ["Pazu", "Ön kol"],
            steps: [
                "Ayakta, dambıl veya barı avuçlar öne bakacak şekilde tut.",
                "Dirsekleri gövdenin yanında sabit tut.",
                "Ağırlığı omuza doğru kaldır, tepede pazuyu sık.",
                "Kollar tamamen açılana kadar yavaşça indir."
            ],
            mistakes: ["Gövdeyi sallayarak kaldırmak", "Dirsekleri öne kaydırmak", "Hızlı ve kontrolsüz iniş"],
            tip: nil
        ),
        "triceps-pushdown": ExerciseGuide(
            symbol: "figure.strengthtraining.traditional",
            muscles: ["Arka kol"],
            steps: [
                "Kablo makinesine dön, tutamağı göğüs hizasında tut.",
                "Dirsekleri gövdenin yanında sabitle.",
                "Kolları tamamen açılana kadar aşağı it, altta arka kolu sık.",
                "Dirsekleri hareket ettirmeden geri gel."
            ],
            mistakes: ["Dirsekleri öne-arkaya oynatmak", "Gövdeyle bastırmak"],
            tip: nil
        ),
        "leg-press": ExerciseGuide(
            symbol: "figure.strengthtraining.functional",
            muscles: ["Ön bacak", "Kalça", "Arka bacak"],
            steps: [
                "Sırtını ve kalçanı minderine tam yasla, ayakları platformda omuz genişliğinde koy.",
                "Kilitleri aç, dizler göğsüne doğru yaklaşık 90° olana kadar kontrollü indir.",
                "Topuklarından iterek platformu yukarı gönder.",
                "Tepede dizleri tamamen kilitleme."
            ],
            mistakes: ["Kalçanın minderden kalkması", "Dizleri kilitlemek", "Dizlerin içe çökmesi"],
            tip: nil
        ),
        "lunge": ExerciseGuide(
            symbol: "figure.strengthtraining.functional",
            muscles: ["Ön bacak", "Kalça", "Denge"],
            steps: [
                "Dik dur, bir adım öne at.",
                "Her iki diz yaklaşık 90° olana kadar gövdeyi dik tutarak in.",
                "Öndeki topuktan iterek başlangıca dön.",
                "Bacak değiştirerek tekrarla."
            ],
            mistakes: ["Öndeki dizin içe kaçması", "Gövdeyi öne eğmek", "Adımı çok kısa atmak"],
            tip: nil
        ),
        "crunch": ExerciseGuide(
            symbol: "figure.core.training",
            muscles: ["Karın"],
            steps: [
                "Sırtüstü uzan, dizleri bük, ayaklar yerde.",
                "Elleri göğsünde çapraz tut ya da şakaklarına hafifçe dokundur.",
                "Karnını sıkarak omuzlarını yerden kaldır.",
                "Kontrollü şekilde geri in."
            ],
            mistakes: ["Elleriyle başını çekmek", "Hızlı, savurmalı tekrar", "Nefesi tutmak"],
            tip: nil
        ),
        "plank": ExerciseGuide(
            symbol: "figure.core.training",
            muscles: ["Karın", "Gövde", "Omuz"],
            steps: [
                "Dirsekler omuzların altında olacak şekilde ön kollarına yaslan.",
                "Bacakları geriye uzat, vücut baştan topuğa düz bir çizgi olsun.",
                "Karın ve kalçayı sık, normal nefes almaya devam et.",
                "Formu bozmadan süreyi tamamla."
            ],
            mistakes: ["Kalçanın düşmesi", "Kalçanın fazla yukarıda olması", "Nefesi tutmak"],
            tip: nil
        ),
        "romanian-deadlift": ExerciseGuide(
            symbol: "figure.strengthtraining.traditional",
            muscles: ["Arka bacak", "Kalça", "Bel"],
            steps: [
                "Barı kalça hizasında tut, dizler hafif bükülü.",
                "Kalçayı geriye iterek gövdeyi öne eğ; bar bacaklarına yakın kayarak insin.",
                "Arka bacakta gerginlik hissettiğinde (genelde diz altı) dur.",
                "Kalçayı öne iterek doğrul."
            ],
            mistakes: ["Sırtı yuvarlamak", "Dizleri fazla bükerek squat'a çevirmek", "Barı vücuttan uzaklaştırmak"],
            tip: nil
        ),
        "lateral-raise": ExerciseGuide(
            symbol: "figure.strengthtraining.traditional",
            muscles: ["Yan omuz"],
            steps: [
                "Dambılları yanlarda tut, dirsekler hafif bükülü.",
                "Kolları omuz hizasına kadar yanlara kaldır.",
                "Tepede kısa bir an bekle.",
                "Yavaşça indir."
            ],
            mistakes: ["Gövdeyle savurmak", "Omuzları kulağa doğru kaldırmak", "Ağır ağırlıkla kısa hareket"],
            tip: "Hafif ağırlık ve kontrollü tempo bu harekette daha verimli."
        ),
        "cable-row": ExerciseGuide(
            symbol: "figure.rower",
            muscles: ["Orta sırt", "Kanatlar", "Pazu"],
            steps: [
                "Ayakları platforma koy, dizler hafif bükülü, sırt dik otur.",
                "Tutamağı karnına doğru çek, dirsekler gövdeye yakın geriye gitsin.",
                "Kürek kemiklerini birbirine yaklaştır.",
                "Kollar uzayana kadar kontrollü bırak, gövde dik kalsın."
            ],
            mistakes: ["Gövdeyi ileri geri savurmak", "Omuzları yukarı kaldırmak"],
            tip: nil
        ),
        "leg-curl": ExerciseGuide(
            symbol: "figure.strengthtraining.functional",
            muscles: ["Arka bacak"],
            steps: [
                "Makineye ayarla: dizlerin makinenin dönme noktasıyla hizalı olsun.",
                "Pedi topuklarına doğru kıvırarak çek.",
                "En üstte kısa bir an sık.",
                "Kontrollü şekilde geri bırak."
            ],
            mistakes: ["Kalçayı kaldırmak", "Ağırlığı düşürür gibi bırakmak"],
            tip: nil
        ),
        "calf-raise": ExerciseGuide(
            symbol: "figure.strengthtraining.functional",
            muscles: ["Baldır"],
            steps: [
                "Ayak uçlarınla bir basamağın kenarına bas, topuklar boşta.",
                "Topuklarını aşağıda hafif esneme hissedene kadar indir.",
                "Parmak uçlarına olabildiğince yüksel, tepede bekle.",
                "Yavaşça in."
            ],
            mistakes: ["Yaylanarak hızlı tekrar", "Hareketi yarım yapmak"],
            tip: nil
        ),
        "burpee": ExerciseGuide(
            symbol: "figure.highintensity.intervaltraining",
            muscles: ["Tüm vücut", "Kondisyon"],
            steps: [
                "Ayakta başla, çömelip ellerini yere koy.",
                "Ayaklarını geriye atarak şınav pozisyonuna geç.",
                "Ayaklarını ellerine doğru geri getir.",
                "Sıçrayarak kalk, kolları yukarı uzat."
            ],
            mistakes: ["Şınav pozisyonunda kalçanın düşmesi", "Sert iniş"],
            tip: nil
        ),
        "jump-rope": ExerciseGuide(
            symbol: "figure.jumprope",
            muscles: ["Baldır", "Kondisyon", "Omuz"],
            steps: [
                "İpi bileklerinle çevir, dirsekler gövdeye yakın.",
                "Ayak uçlarında, alçak ve ritmik zıpla.",
                "Dizleri hafif bükülü tutarak yumuşak in."
            ],
            mistakes: ["Kollarla büyük daireler çizmek", "Gereğinden yüksek zıplamak"],
            tip: nil
        ),
        "running": ExerciseGuide(
            symbol: "figure.run",
            muscles: ["Bacaklar", "Kondisyon"],
            steps: [
                "Gövde dik, hafif öne eğik; omuzlar gevşek.",
                "Kısa ve sık adımlarla, ayak vücudun altına yakın bassın.",
                "Kollar dirsekten yaklaşık 90° bükülü, öne-arkaya sallansın.",
                "Konuşabileceğin bir tempoyla başla, süreyi kademeli artır."
            ],
            mistakes: ["Çok uzun adım atıp topukla sert basmak", "Haftalık mesafeyi aniden artırmak"],
            tip: nil
        ),
        "rowing": ExerciseGuide(
            symbol: "figure.rower",
            muscles: ["Bacaklar", "Sırt", "Kondisyon"],
            steps: [
                "Sıra: bacaklar → gövde → kollar.",
                "Bacaklarınla it, sonra gövdeyi hafif geriye yasla, en son kolu karnına çek.",
                "Dönüşte ters sırayla: kollar → gövde → bacaklar."
            ],
            mistakes: ["Hareketi kollarla başlatmak", "Sırtı yuvarlamak"],
            tip: nil
        )
    ]
}
