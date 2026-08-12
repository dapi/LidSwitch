import Darwin
import LidSwitchDaemonCore

testInitialAndDuplicateObservations()
testWorkClose()
testSleepAcknowledgementIsTerminal()
testFeedbackDeadlineIsTerminal()
testOpeningCancelsPendingSleep()
testLeaseLossFailsSafe()
testStaleGenerationAndEventAreIgnored()

print("All LidSwitchDaemonCore checks passed")

private func testInitialAndDuplicateObservations() {
    var machine = ManagedLidStateMachine()
    _ = machine.activate(policy: .work, generation: "g1")
    check(machine.observeLid(isClosed: false, makeEventID: { "e0" }).isEmpty, "Initial open is silent")
    check(machine.observeLid(isClosed: false, makeEventID: { "e1" }).isEmpty, "Duplicate open is silent")
    _ = machine.observeLid(isClosed: true, makeEventID: { "e2" })
    check(machine.observeLid(isClosed: true, makeEventID: { "e3" }).isEmpty, "Duplicate closed is silent")
    check(machine.observeLid(isClosed: nil, makeEventID: { "e4" }).isEmpty, "Unknown is silent")
    check(machine.observeLid(isClosed: true, makeEventID: { "e5" }).isEmpty, "Unknown breaks transition chain")
}

private func testWorkClose() {
    var machine = ManagedLidStateMachine()
    check(machine.activate(policy: .work, generation: "g1") == [
        .setSleepDisabled(true), .armLeaseDeadline(generation: "g1")
    ], "Activation inhibits sleep and arms lease")
    _ = machine.observeLid(isClosed: false, makeEventID: { "unused" })
    check(machine.observeLid(isClosed: true, makeEventID: { "work-1" }) == [
        .notifyLidClosed(eventID: "work-1", policy: .work)
    ], "Work close notifies without sleep")
}

private func testSleepAcknowledgementIsTerminal() {
    var machine = ManagedLidStateMachine()
    _ = machine.activate(policy: .sleep, generation: "g1")
    _ = machine.observeLid(isClosed: false, makeEventID: { "unused" })
    check(machine.observeLid(isClosed: true, makeEventID: { "sleep-1" }) == [
        .notifyLidClosed(eventID: "sleep-1", policy: .sleep),
        .armFeedbackDeadline(eventID: "sleep-1")
    ], "Sleep close notifies and arms deadline")
    check(machine.feedbackFinished(eventID: "sleep-1", generation: "g1") == [
        .cancelFeedbackDeadline(eventID: "sleep-1"),
        .setSleepDisabled(false),
        .requestSystemSleep
    ], "Acknowledgement restores native sleep before explicit sleep")
    check(machine.feedbackDeadlineExpired(eventID: "sleep-1").isEmpty, "Deadline loses race after acknowledgement")
}

private func testFeedbackDeadlineIsTerminal() {
    var machine = ManagedLidStateMachine()
    _ = machine.activate(policy: .sleep, generation: "g1")
    _ = machine.observeLid(isClosed: false, makeEventID: { "unused" })
    _ = machine.observeLid(isClosed: true, makeEventID: { "sleep-2" })
    check(machine.feedbackDeadlineExpired(eventID: "sleep-2") == [
        .cancelFeedbackDeadline(eventID: "sleep-2"),
        .setSleepDisabled(false),
        .requestSystemSleep
    ], "Deadline fails safe")
    check(machine.feedbackFinished(eventID: "sleep-2", generation: "g1").isEmpty, "Late acknowledgement is ignored")
}

private func testOpeningCancelsPendingSleep() {
    var machine = ManagedLidStateMachine()
    _ = machine.activate(policy: .sleep, generation: "g-open")
    _ = machine.observeLid(isClosed: false, makeEventID: { "unused" })
    _ = machine.observeLid(isClosed: true, makeEventID: { "sleep-open" })
    check(machine.observeLid(isClosed: false, makeEventID: { "unused" }) == [
        .cancelFeedbackDeadline(eventID: "sleep-open"),
        .notifySleepCancelled(eventID: "sleep-open")
    ], "Opening lid cancels pending sleep")
    check(machine.feedbackDeadlineExpired(eventID: "sleep-open").isEmpty, "Cancelled deadline cannot sleep")
    check(machine.observeLid(isClosed: true, makeEventID: { "sleep-again" }) == [
        .notifyLidClosed(eventID: "sleep-again", policy: .sleep),
        .armFeedbackDeadline(eventID: "sleep-again")
    ], "Reclosing starts a new sleep warning")
}

private func testLeaseLossFailsSafe() {
    var openMachine = ManagedLidStateMachine()
    _ = openMachine.activate(policy: .work, generation: "g1")
    _ = openMachine.observeLid(isClosed: false, makeEventID: { "unused" })
    check(openMachine.leaseExpired(generation: "g1") == [.setSleepDisabled(false)], "Open-lid lease loss restores native sleep")

    var closedMachine = ManagedLidStateMachine()
    _ = closedMachine.activate(policy: .work, generation: "g2")
    _ = closedMachine.observeLid(isClosed: false, makeEventID: { "unused" })
    _ = closedMachine.observeLid(isClosed: true, makeEventID: { "work-2" })
    check(closedMachine.leaseExpired(generation: "g2") == [
        .setSleepDisabled(false), .requestSystemSleep
    ], "Closed-lid lease loss restores and sleeps")
}

private func testStaleGenerationAndEventAreIgnored() {
    var machine = ManagedLidStateMachine()
    _ = machine.activate(policy: .sleep, generation: "new")
    check(machine.heartbeat(generation: "old").isEmpty, "Stale heartbeat ignored")
    _ = machine.observeLid(isClosed: false, makeEventID: { "unused" })
    _ = machine.observeLid(isClosed: true, makeEventID: { "current" })
    check(machine.feedbackFinished(eventID: "stale", generation: "new").isEmpty, "Stale event ignored")
    check(machine.feedbackFinished(eventID: "current", generation: "old").isEmpty, "Stale generation ignored")
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Check failed: \(message)\n", stderr)
        exit(1)
    }
}
