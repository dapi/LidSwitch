public enum ManagedLidPolicy: Int, CaseIterable, Equatable, Sendable {
    case work = 1
    case sleep = 2
}

public enum ManagedLidState: Equatable, Sendable {
    case inactive
    case active(policy: ManagedLidPolicy, generation: String)
    case pendingSleep(policy: ManagedLidPolicy, generation: String, eventID: String)
}

public enum ManagedLidAction: Equatable, Sendable {
    case setSleepDisabled(Bool)
    case notifyLidClosed(eventID: String, policy: ManagedLidPolicy)
    case notifySleepCancelled(eventID: String)
    case armLeaseDeadline(generation: String)
    case armFeedbackDeadline(eventID: String)
    case cancelFeedbackDeadline(eventID: String)
    case requestSystemSleep
}

public struct ManagedLidStateMachine: Sendable {
    public private(set) var state: ManagedLidState = .inactive
    public private(set) var lidIsClosed: Bool?

    public init() {}

    public mutating func activate(
        policy: ManagedLidPolicy,
        generation: String
    ) -> [ManagedLidAction] {
        state = .active(policy: policy, generation: generation)
        return [
            .setSleepDisabled(true),
            .armLeaseDeadline(generation: generation)
        ]
    }

    public mutating func heartbeat(generation: String) -> [ManagedLidAction] {
        guard currentGeneration == generation else { return [] }
        return [.armLeaseDeadline(generation: generation)]
    }

    public mutating func observeLid(
        isClosed: Bool?,
        makeEventID: () -> String
    ) -> [ManagedLidAction] {
        let previous = lidIsClosed
        lidIsClosed = isClosed

        if isClosed == false,
           case .pendingSleep(let policy, let generation, let eventID) = state {
            state = .active(policy: policy, generation: generation)
            return [
                .cancelFeedbackDeadline(eventID: eventID),
                .notifySleepCancelled(eventID: eventID)
            ]
        }

        guard previous == false, isClosed == true else { return [] }
        guard case .active(let policy, let generation) = state else { return [] }

        let eventID = makeEventID()
        switch policy {
        case .work:
            return [.notifyLidClosed(eventID: eventID, policy: .work)]
        case .sleep:
            state = .pendingSleep(policy: .sleep, generation: generation, eventID: eventID)
            return [
                .notifyLidClosed(eventID: eventID, policy: .sleep),
                .armFeedbackDeadline(eventID: eventID)
            ]
        }
    }

    public mutating func feedbackFinished(
        eventID: String,
        generation: String
    ) -> [ManagedLidAction] {
        guard case .pendingSleep(_, let currentGeneration, let currentEventID) = state,
              currentGeneration == generation,
              currentEventID == eventID else { return [] }
        state = .inactive
        return safeSleepActions(eventID: eventID)
    }

    public mutating func feedbackDeadlineExpired(eventID: String) -> [ManagedLidAction] {
        guard case .pendingSleep(_, _, let currentEventID) = state,
              currentEventID == eventID else { return [] }
        state = .inactive
        return safeSleepActions(eventID: eventID)
    }

    public mutating func leaseExpired(generation: String) -> [ManagedLidAction] {
        guard currentGeneration == generation else { return [] }
        let pendingEventID: String?
        if case .pendingSleep(_, _, let eventID) = state {
            pendingEventID = eventID
        } else {
            pendingEventID = nil
        }
        state = .inactive

        var actions: [ManagedLidAction] = []
        if let pendingEventID {
            actions.append(.cancelFeedbackDeadline(eventID: pendingEventID))
        }
        actions.append(.setSleepDisabled(false))
        if lidIsClosed == true || pendingEventID != nil {
            actions.append(.requestSystemSleep)
        }
        return actions
    }

    public mutating func deactivate() -> [ManagedLidAction] {
        guard state != .inactive else { return [.setSleepDisabled(false)] }
        guard let generation = currentGeneration else { return [.setSleepDisabled(false)] }
        return leaseExpired(generation: generation)
    }

    private var currentGeneration: String? {
        switch state {
        case .inactive: return nil
        case .active(_, let generation): return generation
        case .pendingSleep(_, let generation, _): return generation
        }
    }

    private func safeSleepActions(eventID: String) -> [ManagedLidAction] {
        [
            .cancelFeedbackDeadline(eventID: eventID),
            .setSleepDisabled(false),
            .requestSystemSleep
        ]
    }
}
