import AppKit
import LidSwitchDaemonProtocol

enum LidSoundPreference: String {
    case all
    case workOnly
    case sleepOnly
    case none

    var workEnabled: Bool { self == .all || self == .workOnly }
    var sleepEnabled: Bool { self == .all || self == .sleepOnly }
}

final class LidOutcomeSoundPlayer: NSObject, NSSoundDelegate {
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
        guard soundEnabled else { return }

        let name = policy == .work ? "Glass" : "Sosumi"
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            if policy == .work { completion?() }
            return
        }
        currentSound = sound
        sound.delegate = self
        if policy == .sleep { sound.loops = true }
        if !sound.play() {
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
