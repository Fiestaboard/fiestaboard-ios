import Foundation
import FiestaBoardKit
import FiestaBoardRender

public extension BoardFrame {
    /// The frame `/board/current-message` reports for a board (thumbnails of
    /// the other displays on Home).
    init(_ message: CurrentBoardMessage, rows: Int, cols: Int) {
        let layers = (message.layers ?? []).compactMap { layer -> PixelLayer? in
            guard let data = Data(base64Encoded: layer.rgba) else { return nil }
            return PixelLayer(x: layer.x, y: layer.y, w: layer.width, h: layer.height, rgba: data)
        }
        self.init(rows: message.rows ?? rows, cols: message.cols ?? cols, codes: message.characters,
                  message: message.characters == nil ? message.message : nil, layers: layers)
    }
}

/// "Next on the schedule" for Home: the first enabled weekly entry that
/// starts after `now`, today or within the next week. Times are the server's
/// wall-clock `HH:MM` (`resolved_start_time` wins, so sun-relative entries
/// use the server's resolution) compared against `now` in `calendar`'s zone;
/// the caller passes the device calendar, which assumes the device and the
/// server share a time zone — the label says "at 7:00", never a date.
public struct ScheduleUpNext: Sendable, Equatable {
    public let entryID: String
    public let pageID: String
    /// `HH:MM`, as the server reports it.
    public let startTime: String
    /// 0 = today, 1 = tomorrow, … 6.
    public let daysAhead: Int

    public static func next(_ entries: [ScheduleEntry], now: Date, calendar: Calendar = .current) -> ScheduleUpNext? {
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: now)
        guard let hour = parts.hour, let minute = parts.minute, let weekday = parts.weekday else { return nil }
        let nowMinutes = hour * 60 + minute
        var best: (key: Int, value: ScheduleUpNext)?
        for entry in entries where entry.enabled && (entry.recurrenceType ?? "weekly") == "weekly" {
            guard let start = minutes(entry.resolvedStartTime ?? entry.startTime) else { continue }
            for ahead in 0..<7 {
                if ahead == 0 && start <= nowMinutes { continue }
                // Calendar weekday: 1 = Sunday … 7 = Saturday.
                let day = (weekday - 1 + ahead) % 7 + 1
                guard runs(entry, onWeekday: day) else { continue }
                let key = ahead * 1440 + start
                if best == nil || key < best!.key {
                    best = (key, ScheduleUpNext(entryID: entry.id, pageID: entry.pageID,
                                                startTime: entry.resolvedStartTime ?? entry.startTime, daysAhead: ahead))
                }
                break
            }
        }
        return best?.value
    }

    /// "today at 07:00" / "tomorrow at 07:00" / "Monday at 07:00".
    public func whenText(now: Date, calendar: Calendar = .current) -> String {
        let time = Self.displayTime(startTime)
        switch daysAhead {
        case 0: return "today at \(time)"
        case 1: return "tomorrow at \(time)"
        default:
            let weekday = calendar.component(.weekday, from: now)
            let index = (weekday - 1 + daysAhead) % 7
            return "\(calendar.standaloneWeekdaySymbols[index]) at \(time)"
        }
    }

    static func displayTime(_ hhmm: String) -> String {
        guard let total = minutes(hhmm) else { return hhmm }
        let h = total / 60, m = total % 60
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hour12, m, h < 12 ? "AM" : "PM")
    }

    static func minutes(_ hhmm: String) -> Int? {
        let bits = hhmm.split(separator: ":")
        guard bits.count >= 2, let h = Int(bits[0]), let m = Int(bits[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    static func runs(_ entry: ScheduleEntry, onWeekday day: Int) -> Bool {
        switch entry.dayPattern {
        case "all": return true
        case "weekdays": return (2...6).contains(day)
        case "weekends": return day == 1 || day == 7
        case "custom":
            let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            return (entry.customDays ?? []).contains { $0.lowercased() == names[day - 1] }
        default: return false
        }
    }
}
