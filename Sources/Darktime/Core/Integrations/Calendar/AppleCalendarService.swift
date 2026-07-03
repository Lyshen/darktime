import EventKit
import Foundation

@MainActor
final class AppleCalendarService {
    private let eventStore = EKEventStore()

    func requestAccess() async throws {
        _ = try await requestCalendarAccess()
    }

    func authorizationStatus() -> (status: String, canReadWrite: Bool) {
        let status = EKEventStore.authorizationStatus(for: .event)
        return (
            status: statusName(status),
            canReadWrite: hasFullCalendarAccess(status)
        )
    }

    func calendarsIfAuthorized() -> [CalendarSnapshot] {
        guard hasFullCalendarAccess(EKEventStore.authorizationStatus(for: .event)) else {
            return []
        }

        return eventStore.calendars(for: .event)
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map(calendarSnapshot)
    }
}

