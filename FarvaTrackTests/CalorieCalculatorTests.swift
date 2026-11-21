import XCTest
@testable import FarvaTrack

final class CalorieCalculatorTests: XCTestCase {

    func testBMRForMale() {
        // 10*80 + 6.25*180 - 5*30 + 5 = 1780
        let bmr = CalorieCalculator.bmr(weightKg: 80, heightCm: 180, age: 30, gender: .male)
        XCTAssertEqual(bmr, 1780, accuracy: 0.01)
    }

    func testBMRForFemale() {
        // 10*60 + 6.25*165 - 5*25 - 161 = 1345.25
        let bmr = CalorieCalculator.bmr(weightKg: 60, heightCm: 165, age: 25, gender: .female)
        XCTAssertEqual(bmr, 1345.25, accuracy: 0.01)
    }

    func testCalorieGoalMaintain() {
        let goal = CalorieCalculator.calorieGoal(tdee: 1780 * 1.55, goal: .maintain)
        XCTAssertEqual(goal, 2760)
    }

    func testCalorieGoalNeverBelowFloor() {
        let goal = CalorieCalculator.calorieGoal(tdee: 1300, goal: .loseWeight)
        XCTAssertEqual(goal, 1200)
    }

    func testWaterGoalIsRoundedToFifty() {
        // 70*33 + 300 = 2610 -> 2600
        XCTAssertEqual(CalorieCalculator.waterGoalMl(weightKg: 70, activity: .moderate), 2600)
    }

    func testSedentaryCapsStepGoal() {
        XCTAssertEqual(CalorieCalculator.stepGoal(goal: .loseWeight, activity: .sedentary), 7_000)
        XCTAssertEqual(CalorieCalculator.stepGoal(goal: .loseWeight, activity: .active), 10_000)
    }

    func testSleepHoursByAge() {
        XCTAssertEqual(CalorieCalculator.sleepHours(age: 15), 9.0)
        XCTAssertEqual(CalorieCalculator.sleepHours(age: 30), 8.0)
        XCTAssertEqual(CalorieCalculator.sleepHours(age: 70), 7.5)
    }

    func testExerciseCalories() {
        // 9,8 × 70 × 0,5 saat = 343
        XCTAssertEqual(CalorieCalculator.exerciseCalories(met: 9.8, weightKg: 70, minutes: 30), 343, accuracy: 0.01)
    }

    func testWalkingCalories() {
        XCTAssertEqual(CalorieCalculator.walkingCalories(distanceKm: 7, weightKg: 70), 259.7, accuracy: 0.01)
    }

    func testEstimatedDistanceFromSteps() {
        XCTAssertEqual(CalorieCalculator.estimatedDistanceKm(steps: 10_000, heightCm: 175), 7.2625, accuracy: 0.001)
    }

    func testMacroTargetsForMaintainGoal() {
        let targets = CalorieCalculator.macroTargets(calories: 2_000, goal: .maintain)
        XCTAssertEqual(targets.proteinG, 100)
        XCTAssertEqual(targets.carbsG, 250)
        XCTAssertEqual(targets.fatG, 67)
    }

    func testAuthErrorCodesAreMapped() {
        let wrongPassword = NSError(domain: AppError.firebaseAuthErrorDomain, code: 17009)
        let emailInUse = NSError(domain: AppError.firebaseAuthErrorDomain, code: 17007)
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(AppError.map(wrongPassword), .wrongCredentials)
        XCTAssertEqual(AppError.map(emailInUse), .emailAlreadyInUse)
        XCTAssertEqual(AppError.map(offline), .network)
    }
}
