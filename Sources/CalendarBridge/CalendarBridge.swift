import CoreGraphics
import EventKit
import Foundation

enum BridgeError: Error {
    case invalidArguments(String)
    case calendarAccessRequired(String)
    case calendarNotFound(String)
    case eventNotFound(String)
    case calendarNotWritable(String)
    case invalidDate(String)
    case invalidAvailability(String)
    case eventKit(String)
}

struct ErrorPayload: Encodable {
    let code: String
    let message: String
}

struct ErrorResponse: Encodable {
    let ok = false
    let error: ErrorPayload
}

struct SuccessResponse<T: Encodable>: Encodable {
    let ok = true
    let data: T
}

struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

struct Options {
    let command: String
    let values: [String: String]
    let flags: Set<String>

    func value(_ key: String) -> String? {
        values[key]
    }

    func required(_ key: String) throws -> String {
        guard let value = values[key], !value.isEmpty else {
            throw BridgeError.invalidArguments("Missing required option --\(key).")
        }
        return value
    }
}

struct AuthorizationSnapshot: Encodable {
    let status: String
    let canReadWrite: Bool
}

struct RequestAccessSnapshot: Encodable {
    let granted: Bool
    let status: String
}

struct CalendarSnapshot: Encodable {
    let provider: String
    let calendarId: String
    let title: String
    let sourceTitle: String
    let sourceType: String
    let type: String
    let allowsContentModifications: Bool
    let color: String?
}

struct EventSnapshot: Encodable {
    let provider: String
    let eventId: String?
    let calendarItemId: String
    let externalId: String?
    let calendarId: String
    let calendarTitle: String
    let title: String
    let start: String
    let end: String
    let allDay: Bool
    let availability: String
    let location: String?
    let notes: String?
    let url: String?
    let hasRecurrenceRules: Bool
    let lastModified: String?
}

struct FreeSlotSnapshot: Encodable {
    let start: String
    let end: String
    let durationMinutes: Int
}

@main
struct CalendarBridge {
    @MainActor
    static func main() async {
        let launchArguments = normalizedLaunchArguments(CommandLine.arguments)
        guard launchArguments.count >= 2 else {
            launchCalendarAppUI()
            return
        }

        var outputPath: String?
        do {
            let options = try parseOptions(launchArguments)
            outputPath = options.value("output")
            let result = try await run(options: options)
            printEncoded(result, outputPath: outputPath)
        } catch {
            printEncoded(errorResponse(from: error), outputPath: outputPath)
            Foundation.exit(1)
        }
    }
}

func normalizedLaunchArguments(_ args: [String]) -> [String] {
    guard let executable = args.first else {
        return args
    }

    return [executable] + args.dropFirst().filter { !$0.hasPrefix("-psn_") }
}

@MainActor
func run(options: Options) async throws -> AnyEncodable {
    let eventStore = EKEventStore()

    switch options.command {
    case "help", "--help", "-h":
        return success([
            "authorization-status",
            "request-access",
            "list-calendars",
            "list-events",
            "create-event",
            "update-event",
            "delete-event",
            "find-free-slots"
        ])
    case "authorization-status":
        let status = EKEventStore.authorizationStatus(for: .event)
        return success(AuthorizationSnapshot(
            status: statusName(status),
            canReadWrite: hasFullCalendarAccess(status)
        ))
    case "request-access":
        let granted = try await requestCalendarAccess(eventStore: eventStore)
        let status = EKEventStore.authorizationStatus(for: .event)
        return success(RequestAccessSnapshot(
            granted: granted,
            status: statusName(status)
        ))
    case "list-calendars":
        try ensureFullCalendarAccess()
        let calendars = eventStore.calendars(for: .event).map(calendarSnapshot)
        return success(calendars)
    case "list-events":
        try ensureFullCalendarAccess()
        let calendars = try resolveCalendars(eventStore: eventStore, calendarId: options.value("calendar-id"))
        let start = try parseDate(options.required("start"), optionName: "start")
        let end = try parseDate(options.required("end"), optionName: "end")
        try validateDateRange(start: start, end: end)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map(eventSnapshot)
        return success(events)
    case "create-event":
        try ensureFullCalendarAccess()
        let event = EKEvent(eventStore: eventStore)
        event.title = try options.required("title")
        event.startDate = try parseDate(options.required("start"), optionName: "start")
        event.endDate = try parseDate(options.required("end"), optionName: "end")
        try validateDateRange(start: event.startDate, end: event.endDate)
        event.calendar = try writableCalendar(eventStore: eventStore, calendarId: options.value("calendar-id"))
        event.notes = options.value("notes")
        event.location = options.value("location")
        if let urlString = options.value("url"), !urlString.isEmpty {
            event.url = URL(string: urlString)
        }
        if let availability = options.value("availability") {
            event.availability = try parseAvailability(availability)
        }
        try eventStore.save(event, span: .thisEvent, commit: true)
        return success(eventSnapshot(event))
    case "update-event":
        try ensureFullCalendarAccess()
        let eventId = try options.required("event-id")
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw BridgeError.eventNotFound(eventId)
        }
        if let title = options.value("title") {
            event.title = title
        }
        if let startValue = options.value("start") {
            event.startDate = try parseDate(startValue, optionName: "start")
        }
        if let endValue = options.value("end") {
            event.endDate = try parseDate(endValue, optionName: "end")
        }
        try validateDateRange(start: event.startDate, end: event.endDate)
        if let calendarId = options.value("calendar-id") {
            event.calendar = try writableCalendar(eventStore: eventStore, calendarId: calendarId)
        } else if !event.calendar.allowsContentModifications {
            throw BridgeError.calendarNotWritable(event.calendar.calendarIdentifier)
        }
        if let notes = options.value("notes") {
            event.notes = notes.isEmpty ? nil : notes
        }
        if let location = options.value("location") {
            event.location = location.isEmpty ? nil : location
        }
        if let urlString = options.value("url") {
            event.url = urlString.isEmpty ? nil : URL(string: urlString)
        }
        if let availability = options.value("availability") {
            event.availability = try parseAvailability(availability)
        }
        try eventStore.save(event, span: .thisEvent, commit: true)
        return success(eventSnapshot(event))
    case "delete-event":
        try ensureFullCalendarAccess()
        let eventId = try options.required("event-id")
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw BridgeError.eventNotFound(eventId)
        }
        if !event.calendar.allowsContentModifications {
            throw BridgeError.calendarNotWritable(event.calendar.calendarIdentifier)
        }
        let snapshot = eventSnapshot(event)
        try eventStore.remove(event, span: .thisEvent, commit: true)
        return success(snapshot)
    case "find-free-slots":
        try ensureFullCalendarAccess()
        let calendars = try resolveCalendars(eventStore: eventStore, calendarId: options.value("calendar-id"))
        let start = try parseDate(options.required("start"), optionName: "start")
        let end = try parseDate(options.required("end"), optionName: "end")
        try validateDateRange(start: start, end: end)
        let durationMinutesValue = try options.required("duration-minutes")
        guard let durationMinutes = Int(durationMinutesValue), durationMinutes > 0 else {
            throw BridgeError.invalidArguments("--duration-minutes must be a positive integer.")
        }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        return success(findFreeSlots(
            events: events,
            windowStart: start,
            windowEnd: end,
            durationMinutes: durationMinutes
        ))
    default:
        throw BridgeError.invalidArguments("Unknown command '\(options.command)'. Run 'darktime help'.")
    }
}

func success<T: Encodable>(_ data: T) -> AnyEncodable {
    AnyEncodable(SuccessResponse(data: data))
}

func parseOptions(_ args: [String]) throws -> Options {
    guard args.count >= 2 else {
        throw BridgeError.invalidArguments("Missing command. Run 'darktime help'.")
    }

    let command = args[1]
    var values: [String: String] = [:]
    var flags = Set<String>()
    var index = 2

    while index < args.count {
        let argument = args[index]
        guard argument.hasPrefix("--") else {
            throw BridgeError.invalidArguments("Unexpected argument '\(argument)'. Options must start with --.")
        }

        let key = String(argument.dropFirst(2))
        if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
            values[key] = args[index + 1]
            index += 2
        } else {
            values[key] = "true"
            flags.insert(key)
            index += 1
        }
    }

    return Options(command: command, values: values, flags: flags)
}

func requestCalendarAccess(eventStore: EKEventStore) async throws -> Bool {
    if #available(macOS 14.0, *) {
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                DispatchQueue.main.async {
                    if let error {
                        continuation.resume(throwing: BridgeError.eventKit(error.localizedDescription))
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    } else {
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    if let error {
                        continuation.resume(throwing: BridgeError.eventKit(error.localizedDescription))
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
}

func requestCalendarAccess() async throws -> Bool {
    try await requestCalendarAccess(eventStore: EKEventStore())
}

func ensureFullCalendarAccess() throws {
    let status = EKEventStore.authorizationStatus(for: .event)
    guard hasFullCalendarAccess(status) else {
        throw BridgeError.calendarAccessRequired(
            "Calendar access is '\(statusName(status))'. Run 'darktime request-access' and grant full calendar access."
        )
    }
}

func hasFullCalendarAccess(_ status: EKAuthorizationStatus) -> Bool {
    if #available(macOS 14.0, *) {
        return status == .fullAccess
    }

    return status == .authorized
}

func statusName(_ status: EKAuthorizationStatus) -> String {
    if #available(macOS 14.0, *) {
        switch status {
        case .fullAccess:
            return "fullAccess"
        case .writeOnly:
            return "writeOnly"
        default:
            break
        }
    }

    switch status {
    case .notDetermined:
        return "notDetermined"
    case .restricted:
        return "restricted"
    case .denied:
        return "denied"
    case .authorized:
        return "authorized"
    case .fullAccess:
        return "fullAccess"
    case .writeOnly:
        return "writeOnly"
    @unknown default:
        return "unknown"
    }
}

func sourceTypeName(_ sourceType: EKSourceType) -> String {
    switch sourceType {
    case .local:
        return "local"
    case .exchange:
        return "exchange"
    case .calDAV:
        return "calDAV"
    case .mobileMe:
        return "mobileMe"
    case .subscribed:
        return "subscribed"
    case .birthdays:
        return "birthdays"
    @unknown default:
        return "unknown"
    }
}

func calendarTypeName(_ calendarType: EKCalendarType) -> String {
    switch calendarType {
    case .local:
        return "local"
    case .calDAV:
        return "calDAV"
    case .exchange:
        return "exchange"
    case .subscription:
        return "subscription"
    case .birthday:
        return "birthday"
    @unknown default:
        return "unknown"
    }
}

func availabilityName(_ availability: EKEventAvailability) -> String {
    switch availability {
    case .notSupported:
        return "notSupported"
    case .busy:
        return "busy"
    case .free:
        return "free"
    case .tentative:
        return "tentative"
    case .unavailable:
        return "unavailable"
    @unknown default:
        return "unknown"
    }
}

func parseAvailability(_ value: String) throws -> EKEventAvailability {
    switch value {
    case "busy":
        return .busy
    case "free":
        return .free
    case "tentative":
        return .tentative
    case "unavailable":
        return .unavailable
    default:
        throw BridgeError.invalidAvailability("Unsupported availability '\(value)'. Use busy, free, tentative, or unavailable.")
    }
}

func parseDate(_ value: String, optionName: String) throws -> Date {
    let inputDateFormatterWithFractionalSeconds = ISO8601DateFormatter()
    inputDateFormatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let inputDateFormatter = ISO8601DateFormatter()
    inputDateFormatter.formatOptions = [.withInternetDateTime]

    if let date = inputDateFormatterWithFractionalSeconds.date(from: value) {
        return date
    }
    if let date = inputDateFormatter.date(from: value) {
        return date
    }
    throw BridgeError.invalidDate("--\(optionName) must be an ISO-8601 date, for example 2026-06-28T09:00:00+08:00.")
}

func validateDateRange(start: Date, end: Date) throws {
    guard end > start else {
        throw BridgeError.invalidDate("Event end must be after start.")
    }
}

@MainActor
func resolveCalendars(eventStore: EKEventStore, calendarId: String?) throws -> [EKCalendar]? {
    guard let calendarId, !calendarId.isEmpty else {
        return nil
    }

    guard let calendar = eventStore.calendars(for: .event).first(where: { $0.calendarIdentifier == calendarId }) else {
        throw BridgeError.calendarNotFound(calendarId)
    }

    return [calendar]
}

@MainActor
func writableCalendar(eventStore: EKEventStore, calendarId: String?) throws -> EKCalendar {
    let calendar: EKCalendar?
    if let calendarId, !calendarId.isEmpty {
        calendar = eventStore.calendars(for: .event).first(where: { $0.calendarIdentifier == calendarId })
    } else {
        calendar = eventStore.defaultCalendarForNewEvents
    }

    guard let calendar else {
        throw BridgeError.calendarNotFound(calendarId ?? "default")
    }
    guard calendar.allowsContentModifications else {
        throw BridgeError.calendarNotWritable(calendar.calendarIdentifier)
    }
    return calendar
}

func calendarSnapshot(_ calendar: EKCalendar) -> CalendarSnapshot {
    CalendarSnapshot(
        provider: "apple",
        calendarId: calendar.calendarIdentifier,
        title: calendar.title,
        sourceTitle: calendar.source.title,
        sourceType: sourceTypeName(calendar.source.sourceType),
        type: calendarTypeName(calendar.type),
        allowsContentModifications: calendar.allowsContentModifications,
        color: hexColor(calendar.cgColor)
    )
}

func eventSnapshot(_ event: EKEvent) -> EventSnapshot {
    EventSnapshot(
        provider: "apple",
        eventId: event.eventIdentifier,
        calendarItemId: event.calendarItemIdentifier,
        externalId: event.calendarItemExternalIdentifier,
        calendarId: event.calendar.calendarIdentifier,
        calendarTitle: event.calendar.title,
        title: event.title ?? "",
        start: formatDate(event.startDate),
        end: formatDate(event.endDate),
        allDay: event.isAllDay,
        availability: availabilityName(event.availability),
        location: event.location,
        notes: event.notes,
        url: event.url?.absoluteString,
        hasRecurrenceRules: event.hasRecurrenceRules,
        lastModified: event.lastModifiedDate.map(formatDate)
    )
}

func findFreeSlots(events: [EKEvent], windowStart: Date, windowEnd: Date, durationMinutes: Int) -> [FreeSlotSnapshot] {
    let duration = TimeInterval(durationMinutes * 60)
    let busyIntervals = events.compactMap { event -> (start: Date, end: Date)? in
        guard event.availability != .free else {
            return nil
        }

        let start = max(event.startDate, windowStart)
        let end = min(event.endDate, windowEnd)
        guard end > start else {
            return nil
        }
        return (start, end)
    }
    .sorted { lhs, rhs in
        lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
    }

    var merged: [(start: Date, end: Date)] = []
    for interval in busyIntervals {
        guard let last = merged.last else {
            merged.append(interval)
            continue
        }

        if interval.start <= last.end {
            merged[merged.count - 1] = (last.start, max(last.end, interval.end))
        } else {
            merged.append(interval)
        }
    }

    var slots: [FreeSlotSnapshot] = []
    var cursor = windowStart

    for busy in merged {
        if busy.start.timeIntervalSince(cursor) >= duration {
            slots.append(FreeSlotSnapshot(
                start: formatDate(cursor),
                end: formatDate(busy.start),
                durationMinutes: Int(busy.start.timeIntervalSince(cursor) / 60)
            ))
        }
        cursor = max(cursor, busy.end)
    }

    if windowEnd.timeIntervalSince(cursor) >= duration {
        slots.append(FreeSlotSnapshot(
            start: formatDate(cursor),
            end: formatDate(windowEnd),
            durationMinutes: Int(windowEnd.timeIntervalSince(cursor) / 60)
        ))
    }

    return slots
}

func formatDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

func hexColor(_ color: CGColor?) -> String? {
    guard
        let color,
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let converted = color.converted(to: colorSpace, intent: .defaultIntent, options: nil),
        let components = converted.components
    else {
        return nil
    }

    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    if components.count >= 3 {
        red = components[0]
        green = components[1]
        blue = components[2]
    } else if let gray = components.first {
        red = gray
        green = gray
        blue = gray
    } else {
        return nil
    }

    return String(
        format: "#%02X%02X%02X",
        Int(max(0, min(1, red)) * 255),
        Int(max(0, min(1, green)) * 255),
        Int(max(0, min(1, blue)) * 255)
    )
}

func printEncoded<T: Encodable>(_ value: T, outputPath: String? = nil) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
        let data = try encoder.encode(value)
        if let outputPath, !outputPath.isEmpty {
            try data.write(to: URL(fileURLWithPath: outputPath))
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
        let fallback = #"{"ok":false,"error":{"code":"encoding_failed","message":"Failed to encode response."}}"#
        FileHandle.standardOutput.write(Data(fallback.utf8))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

func errorResponse(from error: Error) -> ErrorResponse {
    let payload: ErrorPayload

    switch error {
    case let BridgeError.invalidArguments(message):
        payload = ErrorPayload(code: "invalid_arguments", message: message)
    case let BridgeError.calendarAccessRequired(message):
        payload = ErrorPayload(code: "calendar_access_required", message: message)
    case let BridgeError.calendarNotFound(calendarId):
        payload = ErrorPayload(code: "calendar_not_found", message: "Calendar not found: \(calendarId).")
    case let BridgeError.eventNotFound(eventId):
        payload = ErrorPayload(code: "event_not_found", message: "Event not found: \(eventId).")
    case let BridgeError.calendarNotWritable(calendarId):
        payload = ErrorPayload(code: "calendar_not_writable", message: "Calendar is not writable: \(calendarId).")
    case let BridgeError.invalidDate(message):
        payload = ErrorPayload(code: "invalid_date", message: message)
    case let BridgeError.invalidAvailability(message):
        payload = ErrorPayload(code: "invalid_availability", message: message)
    case let BridgeError.eventKit(message):
        payload = ErrorPayload(code: "eventkit_error", message: message)
    default:
        payload = ErrorPayload(code: "unexpected_error", message: String(describing: error))
    }

    return ErrorResponse(error: payload)
}
