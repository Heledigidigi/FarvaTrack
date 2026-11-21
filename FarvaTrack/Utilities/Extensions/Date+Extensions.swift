import Foundation

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? self
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// Bu tarihten bugüne geçen tam yıl (doğum tarihinden yaş hesabı için).
    var yearsSinceNow: Int {
        Calendar.current.dateComponents([.year], from: self, to: .now).year ?? 0
    }

    /// Örn: "17 Kasım"
    var shortDateString: String {
        formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "tr_TR")))
    }
}
