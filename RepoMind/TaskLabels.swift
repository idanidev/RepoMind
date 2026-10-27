import Foundation

// MARK: - Labels

/// What a task will be labelled with on GitHub when it is published: its kind, as the capture
/// detected it, and whether it goes to the agent.
nonisolated struct TaskLabels: Codable, Hashable {
    var kind: CaptureKind?
    var delegated = false

    /// The GitHub labels, on top of the ones the sync always adds.
    var gitHubLabels: [String] {
        var labels: [String] = []
        if let kind {
            labels.append(Self.gitHubLabel(for: kind))
        }
        if delegated {
            labels.append(Self.agentLabel)
        }
        return labels
    }

    /// The label the agent workflow listens for.
    static let agentLabel = "agent"

    static func gitHubLabel(for kind: CaptureKind) -> String {
        switch kind {
        case .bug: "bug"
        case .feature: "enhancement"
        case .idea: "idea"
        case .chore: "chore"
        }
    }
}

extension CaptureKind: Codable {}

// MARK: - Store

/// Labels per task, in `UserDefaults`, keyed by the task's id.
///
/// Not a field of `TaskItem` yet: a new `@Model` field has to be deployed to the CloudKit
/// schema before a release, and there is no Mac to seed it from today. Labels are read at
/// publish time, which happens on the device that captured the task moments later, so a
/// device-local store covers the real case. Move it into the model with the next schema
/// deploy; nothing else needs to change.
nonisolated enum TaskLabelStore {
    private static let prefix = "taskLabels_"

    static func labels(for taskID: UUID, defaults: UserDefaults = .standard) -> TaskLabels? {
        guard let data = defaults.data(forKey: prefix + taskID.uuidString) else { return nil }
        return try? JSONDecoder().decode(TaskLabels.self, from: data)
    }

    static func set(_ labels: TaskLabels, for taskID: UUID, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(labels) else { return }
        defaults.set(data, forKey: prefix + taskID.uuidString)
    }

    static func remove(for taskID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: prefix + taskID.uuidString)
    }

    /// Every task's labels, on sign-out: the tasks go with the account, and the entries would stay.
    static func removeAll(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Settings → Agent: whether new tasks go to the agent unless the capture says otherwise.
    static var delegatesNewTasks: Bool {
        UserDefaults.standard.bool(forKey: "delegateNewTasks")
    }
}
