import SwiftUI
import Observation

// MARK: - Sekmeler
enum AppTab: Hashable, CaseIterable {
    case dashboard, exercise, nutrition, water, profile

    var title: String {
        switch self {
        case .dashboard: return "Özet"
        case .exercise: return "Egzersiz"
        case .nutrition: return "Beslenme"
        case .water: return "Su"
        case .profile: return "Profil"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .exercise: return "dumbbell.fill"
        case .nutrition: return "fork.knife"
        case .water: return "drop.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

// MARK: - Özet ekranından açılan sayfalar
enum AppRoute: Hashable, CaseIterable, Identifiable {
    case steps, sleep, weight, biologicalWaste, statistics

    var id: Self { self }

    var title: String {
        switch self {
        case .steps: return "Adımlar"
        case .sleep: return "Uyku"
        case .weight: return "Kilo"
        case .biologicalWaste: return "Biyolojik Atık"
        case .statistics: return "İstatistikler"
        }
    }

    var systemImage: String {
        switch self {
        case .steps: return "figure.walk"
        case .sleep: return "moon.stars.fill"
        case .weight: return "scalemass.fill"
        case .biologicalWaste: return "list.bullet.clipboard.fill"
        case .statistics: return "chart.xyaxis.line"
        }
    }

    var tint: Color {
        switch self {
        case .steps: return Color.ftAccentLight
        case .sleep: return Color.ftSleep
        case .weight: return Color.ftWeight
        case .biologicalWaste: return Color.ftWaste
        case .statistics: return Color.ftStats
        }
    }
}

extension AppRoute {
    @ViewBuilder
    var destination: some View {
        switch self {
        case .steps:
            StepsView()
        case .sleep:
            SleepView()
        case .weight:
            WeightView()
        case .biologicalWaste:
            WasteView()
        case .statistics:
            StatisticsView()
        }
    }
}

// MARK: - Yönlendirici
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .dashboard
    var dashboardPath: [AppRoute] = []

    func select(_ tab: AppTab) {
        selectedTab = tab
    }

    /// Özet sekmesine geçip ilgili sayfayı açar.
    func push(_ route: AppRoute) {
        selectedTab = .dashboard
        dashboardPath.append(route)
    }

    func popToRoot() {
        dashboardPath.removeAll()
    }

    /// Widget / bildirim derin bağlantıları: farvatrack://steps, water, sleep, weight, waste
    func handle(_ url: URL) {
        guard url.scheme == "farvatrack" else { return }
        switch url.host {
        case "steps":
            popToRoot()
            push(.steps)
        case "water":
            popToRoot()
            select(.water)
        case "sleep":
            popToRoot()
            push(.sleep)
        case "weight":
            popToRoot()
            push(.weight)
        case "waste":
            popToRoot()
            push(.biologicalWaste)
        default:
            break
        }
    }
}
