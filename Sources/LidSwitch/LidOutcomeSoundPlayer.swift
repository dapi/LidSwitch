import AppKit
import LidSwitchDaemonProtocol

final class LidOutcomeSoundPlayer: NSObject, NSSoundDelegate {
    private var currentSound: NSSound?
    private var completion: (() -> Void)?
    private var currentEventID: String?
    private var warningTimer: Timer?

    func play(policy: DaemonLidPolicy, eventID: String, completion: (() -> Void)? = nil) {
        warningTimer?.invalidate()
        warningTimer = nil
        currentSound?.stop()
        self.completion = nil
        currentEventID = eventID

        let name = policy == .work ? "Glass" : "Sosumi"
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            completion?()
            return
        }
        currentSound = sound
        sound.delegate = self
        self.completion = completion
        if policy == .sleep {
            sound.loops = true
            warningTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                self?.finish()
            }
        }
        if !sound.play() {
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
