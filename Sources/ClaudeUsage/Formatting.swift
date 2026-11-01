import Foundation

enum Formatting {
    /// "Resets at 6:00 AM", "Resets tomorrow at 6:00 AM", "Resets Saturday 10:00 PM".
    static func resetDescription(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return "Resets at \(time)"
        }
        if calendar.isDateInTomorrow(date) {
            return "Resets tomorrow at \(time)"
        }
        if date.timeIntervalSince(now) < 7 * 24 * 3600 {
            return "Resets \(weekday(date)) \(time)"
        }
        return "Resets \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }

    static func planName(_ subscriptionType: String?) -> String? {
        guard let subscriptionType, !subscriptionType.isEmpty else { return nil }
        switch subscriptionType.lowercased() {
        case "pro": return "Pro"
        case "max": return "Max"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return subscriptionType.capitalized
        }
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// One-line summary like the one at the top of claude.ai's usage page.
    static func paceSummary(for usage: UsageResponse, now: Date = Date()) -> String {
        if let session = usage.fiveHour, session.utilization >= 100 {
            return "Session limit reached. \(resetDescription(session.resetsAt, now: now) ?? "")"
        }
        guard let week = usage.sevenDay, let resetsAt = week.resetsAt else {
            return "Usage is up to date."
        }
        let resetDay = calendarDayName(resetsAt, now: now)
        if week.utilization >= 100 {
            return "Weekly limit reached. \(resetDescription(resetsAt, now: now) ?? "")"
        }

        let windowLength: TimeInterval = 7 * 24 * 3600
        let windowStart = resetsAt.addingTimeInterval(-windowLength)
        let elapsed = max(now.timeIntervalSince(windowStart), 0)
        let elapsedFraction = elapsed / windowLength
        let usedFraction = week.utilization / 100

        // Too early in the window to extrapolate meaningfully.
        guard elapsedFraction > 0.05, usedFraction > 0 else {
            return "On track. You should reach \(resetDay)'s reset with room to spare."
        }

        let projected = usedFraction / elapsedFraction
        if projected <= 0.9 {
            return "On track. You should reach \(resetDay)'s reset with room to spare."
        }
        if projected <= 1 {
            return "Cutting it close. At this pace you'll just make it to \(resetDay)'s reset."
        }
        let hitDate = windowStart.addingTimeInterval(elapsed / usedFraction)
        let hitDay = calendarDayName(hitDate, now: now)
        let hitTime = hitDate.formatted(date: .omitted, time: .shortened)
        return "At this pace you'll hit the weekly limit \(hitDay) around \(hitTime)."
    }

    private static func calendarDayName(_ date: Date, now: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) { return "today" }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow" }
        return weekday(date)
    }
}
