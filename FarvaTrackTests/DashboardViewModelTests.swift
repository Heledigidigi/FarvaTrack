import XCTest
@testable import FarvaTrack

@MainActor
final class DashboardViewModelTests: XCTestCase {

    private struct StubSource: DashboardDataSource {
        let result: DashboardSummary
        func summary(for date: Date) async throws -> DashboardSummary { result }
    }

    private struct FailingSource: DashboardDataSource {
        func summary(for date: Date) async throws -> DashboardSummary { throw AppError.network }
    }

    func testProgressUsesUserGoals() async {
        var summary = DashboardSummary()
        summary.steps = 5_000
        summary.waterMl = 1_250
        summary.sleepHours = 4

        var user = AppUser.makeNew(id: "u1", email: "a@b.com", displayName: "Test")
        user.dailyStepGoal = 10_000
        user.dailyWaterGoalMl = 2_500
        user.sleepGoalHours = 8

        let sut = DashboardViewModel(dataSource: StubSource(result: summary))
        sut.updateGoals(from: user)
        await sut.load()

        XCTAssertEqual(sut.stepProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(sut.waterProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(sut.sleepProgress, 0.5, accuracy: 0.001)
    }

    func testZeroGoalDoesNotDivideByZero() async {
        var user = AppUser.makeNew(id: "u1", email: "a@b.com", displayName: "Test")
        user.dailyStepGoal = 0
        let sut = DashboardViewModel(dataSource: StubSource(result: DashboardSummary(steps: 100)))
        sut.updateGoals(from: user)
        await sut.load()
        XCTAssertEqual(sut.stepProgress, 0)
    }

    func testGreetingByHour() {
        XCTAssertEqual(DashboardViewModel.greeting(forHour: 8), "Günaydın")
        XCTAssertEqual(DashboardViewModel.greeting(forHour: 14), "İyi günler")
        XCTAssertEqual(DashboardViewModel.greeting(forHour: 20), "İyi akşamlar")
        XCTAssertEqual(DashboardViewModel.greeting(forHour: 2), "İyi geceler")
    }

    func testEmptySourceProvidesSevenDaysWithoutData() async {
        let sut = DashboardViewModel()
        await sut.load()
        XCTAssertEqual(sut.summary.weeklySteps.count, 7)
        XCTAssertFalse(sut.hasWeeklyStepData)
        XCTAssertTrue(sut.hasLoaded)
    }

    func testBMIUsesProfileWeightWhenNoMeasurementExists() {
        var user = AppUser.makeNew(id: "u1", email: "a@b.com", displayName: "Test")
        user.weightKg = 72
        user.heightCm = 180
        let sut = DashboardViewModel()
        sut.updateGoals(from: user)
        XCTAssertEqual(sut.bmi ?? 0, 22.22, accuracy: 0.01)
    }

    func testLoadFailureSetsErrorMessage() async {
        let sut = DashboardViewModel(dataSource: FailingSource())
        await sut.load()
        XCTAssertEqual(sut.errorMessage, AppError.network.errorDescription)
    }
}

@MainActor
final class AppRouterTests: XCTestCase {
    func testPushSwitchesToDashboardAndAppendsRoute() {
        let router = AppRouter()
        router.select(.water)
        router.push(.sleep)
        XCTAssertEqual(router.selectedTab, .dashboard)
        XCTAssertEqual(router.dashboardPath, [.sleep])
    }

    func testPopToRoot() {
        let router = AppRouter()
        router.push(.steps)
        router.popToRoot()
        XCTAssertTrue(router.dashboardPath.isEmpty)
    }
}