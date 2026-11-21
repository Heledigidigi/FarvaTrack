import Foundation

/// Yaklaşık ortalama besin değerleri (1 porsiyon için). Marka ve tarife göre değişir.
enum FoodLibrary {
    static func template(forKey key: String) -> FoodTemplate? {
        all.first { $0.key == key }
    }

    private static func food(
        _ slug: String, _ name: String, _ serving: String,
        _ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double
    ) -> FoodTemplate {
        FoodTemplate(
            key: "preset.\(slug)", name: name, servingLabel: serving,
            calories: kcal, protein: protein, carbs: carbs, fat: fat
        )
    }

    static let all: [FoodTemplate] = [
        // Kahvaltılık
        food("boiled-egg", "Haşlanmış yumurta", "1 adet (50 g)", 78, 6.3, 0.6, 5.3),
        food("omelette", "Omlet (2 yumurta)", "1 porsiyon (120 g)", 200, 13, 1, 16),
        food("menemen", "Menemen", "1 porsiyon (200 g)", 240, 11, 9, 18),
        food("sucuklu-egg", "Sucuklu yumurta", "1 porsiyon (150 g)", 420, 22, 3, 35),
        food("white-cheese", "Beyaz peynir", "1 dilim (30 g)", 80, 4.5, 1, 6.5),
        food("kashar", "Kaşar peyniri", "1 dilim (20 g)", 70, 5, 0.3, 5.5),
        food("black-olive", "Siyah zeytin", "5 adet (20 g)", 40, 0.3, 1, 4),
        food("honey", "Bal", "1 yemek kaşığı (20 g)", 61, 0.1, 16, 0),
        food("jam", "Reçel", "1 yemek kaşığı (20 g)", 52, 0.1, 13, 0),
        food("butter", "Tereyağı", "1 tatlı kaşığı (10 g)", 72, 0.1, 0, 8),
        food("white-bread", "Beyaz ekmek", "1 dilim (30 g)", 80, 2.5, 15, 1),
        food("whole-bread", "Tam buğday ekmeği", "1 dilim (30 g)", 74, 3.5, 13, 1),
        food("simit", "Simit", "1 adet (120 g)", 330, 10, 60, 6),
        food("oats", "Yulaf ezmesi (kuru)", "1 kase (40 g)", 150, 5, 27, 3),
        food("cheese-borek", "Peynirli börek", "1 dilim (100 g)", 290, 10, 27, 16),
        food("milk", "Süt (tam yağlı)", "1 su bardağı (200 ml)", 124, 6.4, 9.6, 6.6),
        food("yogurt", "Yoğurt (tam yağlı)", "1 kase (150 g)", 95, 5, 7, 5),
        food("ayran", "Ayran", "1 su bardağı (200 ml)", 65, 4, 5, 3),
        // Çorba ve ana yemek
        food("lentil-soup", "Mercimek çorbası", "1 kase (250 ml)", 160, 8, 24, 3),
        food("ezogelin-soup", "Ezogelin çorbası", "1 kase (250 ml)", 140, 6, 22, 3),
        food("chicken-breast", "Tavuk göğsü (ızgara)", "1 porsiyon (100 g)", 165, 31, 0, 3.6),
        food("chicken-thigh", "Tavuk but (fırın)", "1 adet (120 g)", 230, 25, 0, 14),
        food("chicken-shish", "Tavuk şiş", "1 porsiyon (150 g)", 240, 36, 2, 10),
        food("kofte", "Izgara köfte", "5 adet (150 g)", 360, 28, 6, 24),
        food("kuru-fasulye", "Kuru fasulye", "1 porsiyon (250 g)", 300, 16, 40, 8),
        food("chickpea-stew", "Nohut yemeği", "1 porsiyon (250 g)", 330, 15, 42, 11),
        food("etli-turlu", "Etli türlü", "1 porsiyon (250 g)", 280, 14, 20, 16),
        food("green-beans", "Taze fasulye (zeytinyağlı)", "1 porsiyon (200 g)", 150, 3, 14, 9),
        food("karniyarik", "Karnıyarık", "1 adet (250 g)", 360, 16, 20, 25),
        food("iskender", "İskender", "1 porsiyon (300 g)", 780, 38, 55, 45),
        food("doner-meat", "Döner (et)", "1 porsiyon (150 g)", 420, 32, 4, 30),
        food("chicken-wrap", "Tavuk dürüm", "1 adet", 520, 30, 50, 22),
        food("lahmacun", "Lahmacun", "1 adet (120 g)", 280, 13, 36, 9),
        food("pide-minced", "Kıymalı pide", "1 porsiyon (150 g)", 400, 20, 45, 15),
        food("rice-pilaf", "Pirinç pilavı", "1 porsiyon (150 g)", 240, 4.5, 42, 6),
        food("bulgur-pilaf", "Bulgur pilavı", "1 porsiyon (150 g)", 200, 6, 36, 4),
        food("pasta", "Makarna (haşlanmış)", "1 porsiyon (200 g)", 310, 11, 62, 2),
        food("bolognese", "Spagetti bolonez", "1 porsiyon (300 g)", 480, 22, 60, 16),
        food("manti", "Mantı", "1 porsiyon (200 g)", 420, 17, 48, 18),
        food("stuffed-vine-leaves", "Yaprak sarma (zeytinyağlı)", "5 adet (100 g)", 190, 3, 24, 9),
        food("stuffed-peppers", "Dolma biber (etli)", "2 adet (200 g)", 260, 12, 22, 14),
        food("imam-bayildi", "İmam bayıldı", "1 porsiyon (150 g)", 230, 3, 16, 18),
        food("lentil-kofte", "Mercimek köftesi", "3 adet (100 g)", 150, 6, 25, 3),
        food("sea-bass", "Levrek (ızgara)", "1 porsiyon (150 g)", 190, 30, 0, 7),
        food("salmon", "Somon (ızgara)", "1 fileto (150 g)", 310, 33, 0, 19),
        food("tuna-can", "Ton balığı (suda, konserve)", "1 kutu (80 g)", 90, 20, 0, 1),
        food("fries", "Patates kızartması", "1 porsiyon (150 g)", 460, 6, 57, 23),
        food("boiled-potato", "Haşlanmış patates", "1 orta boy (150 g)", 130, 3, 30, 0.2),
        food("quinoa", "Kinoa (pişmiş)", "1 porsiyon (150 g)", 180, 6.6, 32, 3),
        // Salata ve mezeler
        food("shepherd-salad", "Çoban salatası", "1 porsiyon (200 g)", 110, 2, 10, 7),
        food("green-salad", "Mevsim salata (zeytinyağlı)", "1 porsiyon (200 g)", 120, 2, 9, 9),
        food("cacik", "Cacık", "1 kase (150 g)", 70, 4, 5, 4),
        food("hummus", "Humus", "2 yemek kaşığı (30 g)", 70, 2, 5, 5),
        food("avocado", "Avokado", "yarım adet (100 g)", 160, 2, 9, 15),
        // Meyve ve kuruyemiş
        food("apple", "Elma", "1 orta boy (180 g)", 95, 0.5, 25, 0.3),
        food("banana", "Muz", "1 orta boy (120 g)", 105, 1.3, 27, 0.4),
        food("orange", "Portakal", "1 orta boy (150 g)", 62, 1.2, 15, 0.2),
        food("grapes", "Üzüm", "1 avuç (100 g)", 69, 0.7, 18, 0.2),
        food("strawberry", "Çilek", "1 kase (150 g)", 48, 1, 11.5, 0.5),
        food("watermelon", "Karpuz", "1 dilim (300 g)", 90, 1.8, 23, 0.5),
        food("dried-apricot", "Kuru kayısı", "5 adet (40 g)", 95, 1.3, 22, 0.2),
        food("almond", "Badem", "10 adet (12 g)", 70, 2.6, 2.6, 6.1),
        food("walnut", "Ceviz", "1 avuç (30 g)", 196, 4.6, 4.1, 19.6),
        food("hazelnut", "Fındık", "1 avuç (30 g)", 188, 4.5, 5, 18),
        food("peanut-butter", "Fıstık ezmesi", "1 yemek kaşığı (16 g)", 95, 4, 3, 8),
        // Tatlı ve atıştırmalık
        food("dark-chocolate", "Bitter çikolata", "2 kare (20 g)", 110, 1.5, 9, 8),
        food("milk-chocolate", "Sütlü çikolata", "1/4 tablet (25 g)", 135, 2, 14, 8),
        food("baklava", "Baklava", "1 dilim (50 g)", 215, 3, 25, 12),
        food("rice-pudding", "Sütlaç", "1 kase (150 g)", 210, 5, 33, 6),
        food("ice-cream", "Dondurma", "1 top (70 g)", 150, 3, 17, 8),
        food("cookie", "Kurabiye", "2 adet (30 g)", 140, 2, 19, 6),
        food("chips", "Cips", "1 küçük paket (30 g)", 160, 2, 15, 10),
        food("crackers", "Kraker", "1 paket (30 g)", 130, 3, 20, 4),
        food("protein-bar", "Protein bar", "1 adet (50 g)", 200, 20, 20, 7),
        food("whey", "Protein tozu (whey)", "1 ölçek (30 g)", 120, 24, 3, 1.5),
        // İçecekler
        food("tea", "Türk çayı (şekersiz)", "1 bardak (100 ml)", 2, 0, 0, 0),
        food("turkish-coffee", "Türk kahvesi (şekersiz)", "1 fincan (60 ml)", 5, 0.2, 0.5, 0),
        food("sugar-cube", "Kesme şeker", "1 adet (4 g)", 16, 0, 4, 0),
        food("orange-juice", "Portakal suyu", "1 su bardağı (200 ml)", 90, 1.4, 21, 0.4),
        food("cola", "Kola", "1 kutu (330 ml)", 139, 0, 35, 0)
    ]
}
