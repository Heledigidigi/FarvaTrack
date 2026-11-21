import Foundation
import HealthKit

protocol HealthDataProviding {
    var isHealthDataAvailable: Bool { get }
    func requestStatus() async -> HealthAccessStatus
    func requestAuthorization() async throws
    /// `start` gününden `end` gününe kadar her gün için bir kayıt döner (veri yoksa sıfır).
    func activity(from start: Date, to end: Date) async throws -> [DailyActivity]
    /// Yeni veri geldikçe güncel listeyi yayınlar. İlk değer hemen gelir.
    func liveActivity(from start: Date, to end: Date) -> AsyncThrowingStream<[DailyActivity], Error>
}

final class HealthKitManager: HealthDataProviding {
    static let shared = HealthKitManager()
    private init() {}

    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private let energyType = HKQuantityType(.activeEnergyBurned)

    private var readTypes: Set<HKObjectType> { [stepType, distanceType, energyType] }

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - İzin
    func requestStatus() async -> HealthAccessStatus {
        guard isHealthDataAvailable else { return .unavailable }
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
            return status == .unnecessary ? .requested : .notDetermined
        } catch {
            return .notDetermined
        }
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { throw AppError.healthUnavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            throw AppError.health(error.localizedDescription)
        }
    }

    // MARK: - Sorgular
    func activity(from start: Date, to end: Date) async throws -> [DailyActivity] {
        do {
            async let steps = dailySums(stepType, unit: .count(), from: start, to: end)
            async let distance = dailySums(distanceType, unit: .meterUnit(with: .kilo), from: start, to: end)
            async let energy = dailySums(energyType, unit: .kilocalorie(), from: start, to: end)
            let (stepSums, distanceSums, energySums) = try await (steps, distance, energy)

            let calendar = Calendar.current
            let first = calendar.startOfDay(for: start)
            let last = calendar.startOfDay(for: end)
            let dayCount = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1

            return (0..<max(dayCount, 1)).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
                return DailyActivity(
                    date: day,
                    steps: Int((stepSums[day] ?? 0).rounded()),
                    distanceKm: distanceSums[day] ?? 0,
                    activeEnergyKcal: energySums[day] ?? 0
                )
            }
        } catch {
            throw AppError.health(error.localizedDescription)
        }
    }

    func liveActivity(from start: Date, to end: Date) -> AsyncThrowingStream<[DailyActivity], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Adım koleksiyonu her değiştiğinde üç metriği birlikte yeniden okuruz.
                    for try await _ in self.descriptor(for: self.stepType, from: start, to: end).results(for: self.store) {
                        continuation.yield(try await self.activity(from: start, to: end))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AppError.health(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Arka plan teslimi (widget güncellemesi)
    /// Yeni adım verisi geldiğinde iOS uygulamayı kısa süre uyandırır. İzin yoksa sessizce hiçbir şey olmaz.
    func startBackgroundDelivery(onUpdate: @escaping () async -> Void) {
        guard isHealthDataAvailable else { return }
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            Task {
                await onUpdate()
                completionHandler()
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { _, _ in }
    }

    // MARK: - Yardımcılar
    private func descriptor(for type: HKQuantityType, from start: Date, to end: Date) -> HKStatisticsCollectionQueryDescriptor {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: Calendar.current.startOfDay(for: start),
            intervalComponents: DateComponents(day: 1)
        )
    }

    private func dailySums(_ type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async throws -> [Date: Double] {
        let collection = try await descriptor(for: type, from: start, to: end).result(for: store)
        var sums: [Date: Double] = [:]
        collection.enumerateStatistics(from: Calendar.current.startOfDay(for: start), to: end) { statistics, _ in
            sums[statistics.startDate] = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
        }
        return sums
    }
}
