import AppKit
import LidSwitchDaemonProtocol
import os

enum LidSoundPreference: String {
    case all
    case workOnly
    case sleepOnly
    case none

    var workEnabled: Bool { self == .all || self == .workOnly }
    var sleepEnabled: Bool { self == .all || self == .sleepOnly }
}

final class LidOutcomeSoundPlayer: NSObject, NSSoundDelegate {
    private let logger = Logger(subsystem: "me.dapi.LidSwitch", category: "lid-sounds")
    private var currentSound: NSSound?
    private var completion: (() -> Void)?
    private var currentEventID: String?
    private var warningTimer: Timer?

    static let preferenceKey = "lidCloseSoundPreference"

    static var preference: LidSoundPreference {
        guard let rawValue = UserDefaults.standard.string(forKey: preferenceKey),
              let value = LidSoundPreference(rawValue: rawValue) else {
            return .all
        }
        return value
    }

    func play(policy: DaemonLidPolicy, eventID: String, completion: (() -> Void)? = nil) {
        LidSwitchDiagnostics.log("play requested event=\(eventID) policy=\(policy) preference=\(Self.preference.rawValue)")
        warningTimer?.invalidate()
        warningTimer = nil
        currentSound?.stop()
        self.completion = nil
        currentEventID = eventID

        self.completion = completion
        if policy == .sleep {
            warningTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                self?.finish()
            }
        }

        let soundEnabled = policy == .work ? Self.preference.workEnabled : Self.preference.sleepEnabled
        logger.info("Lid event \(eventID, privacy: .public): policy=\(policy.rawValue, privacy: .public), soundEnabled=\(soundEnabled, privacy: .public)")
        LidSwitchDiagnostics.log("sound decision event=\(eventID) enabled=\(soundEnabled)")
        guard soundEnabled else { return }

        let name = policy == .work ? "Glass" : "Sosumi"
        let sound = NSSound(named: NSSound.Name(name))
            ?? NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true)
        guard let sound else {
            logger.error("Could not load system sound \(name, privacy: .public)")
            LidSwitchDiagnostics.log("sound load failed name=\(name)")
            if policy == .work { completion?() }
            return
        }
        currentSound = sound
        sound.delegate = self
        sound.volume = 1
        if policy == .sleep { sound.loops = true }
        let started = sound.play()
        logger.info("Started system sound \(name, privacy: .public): \(started, privacy: .public)")
        LidSwitchDiagnostics.log("sound play name=\(name) started=\(started) duration=\(sound.duration)")
        if !started {
            if policy == .sleep { return }
            finish()
        }
    }

    func cancel(eventID: String) {
        guard currentEventID == eventID else { return }
        warningTimer?.invalidate()
        warningTimer = nil
        currentSound?.stop()
        currentSound = nil
        currentEventID = nil
        completion = nil
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        guard sound === currentSound else { return }
        finish()
    }

    private func finish() {
        let callback = completion
        completion = nil
        warningTimer?.invalidate()
        warningTimer = nil
        currentSound?.stop()
        currentSound = nil
        currentEventID = nil
        callback?()
    }
}
