import Foundation

// Cron job wire types (`/api/cron/jobs…`).

/// Structured schedule on `CronJob` rows. The create/update request bodies send
/// a plain string expression instead.
struct CronJobSchedule: Codable, Equatable, Sendable {
    var display: String?
    var expr: String?
    var kind: String?

    enum CodingKeys: String, CodingKey {
        case display, expr, kind
    }
}

/// One job row from `GET /api/cron/jobs` (also returned by the job mutation
/// endpoints). The backend may include extra fields beyond this consumed set.
struct CronJob: Codable, Equatable, Identifiable, Sendable {
    var deliver: String?
    var enabled: Bool
    var id: String
    var lastError: String?
    var lastRunAt: String?
    var name: String?
    var nextRunAt: String?
    var prompt: String?
    var schedule: CronJobSchedule?
    var scheduleDisplay: String?
    var script: String?
    var state: String?

    enum CodingKeys: String, CodingKey {
        case deliver, enabled, id, name, prompt, schedule, script, state
        case lastError = "last_error"
        case lastRunAt = "last_run_at"
        case nextRunAt = "next_run_at"
        case scheduleDisplay = "schedule_display"
    }
}

/// Request body for `POST /api/cron/jobs`. Unset fields are omitted on the wire.
struct CronJobCreatePayload: Codable, Equatable, Sendable {
    var deliver: String?
    var name: String?
    var prompt: String
    /// Plain schedule expression string (not the structured `CronJobSchedule`).
    var schedule: String

    init(prompt: String, schedule: String, deliver: String? = nil, name: String? = nil) {
        self.prompt = prompt
        self.schedule = schedule
        self.deliver = deliver
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case deliver, name, prompt, schedule
    }
}

/// Request body for `PUT /api/cron/jobs/{id}` — sent wrapped as `{ "updates": … }`.
/// Unset fields are omitted on the wire.
struct CronJobUpdates: Codable, Equatable, Sendable {
    var deliver: String?
    var enabled: Bool?
    var name: String?
    var prompt: String?
    var schedule: String?

    init(deliver: String? = nil, enabled: Bool? = nil, name: String? = nil,
         prompt: String? = nil, schedule: String? = nil) {
        self.deliver = deliver
        self.enabled = enabled
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
    }

    enum CodingKeys: String, CodingKey {
        case deliver, enabled, name, prompt, schedule
    }
}
