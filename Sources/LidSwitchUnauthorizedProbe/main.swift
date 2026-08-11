import Foundation
import LidSwitchDaemonProtocol

let connection = NSXPCConnection(
    machServiceName: LidSwitchDaemonConstants.machServiceName,
    options: .privileged
)
connection.remoteObjectInterface = NSXPCInterface(with: LidSwitchDaemonXPCProtocol.self)

let semaphore = DispatchSemaphore(value: 0)
let lock = NSLock()
var result = 0 // 0 = pending, 1 = rejected, 2 = unexpectedly accepted

func recordResult(_ newResult: Int, message: String) {
    lock.lock()
    guard result == 0 else {
        lock.unlock()
        return
    }
    result = newResult
    lock.unlock()
    fputs(message + "\n", newResult == 2 ? stderr : stdout)
    semaphore.signal()
}

connection.invalidationHandler = {
    recordResult(1, message: "PASS: daemon rejected the unauthorized client.")
}
connection.interruptionHandler = {
    recordResult(1, message: "PASS: daemon interrupted the unauthorized client connection.")
}
connection.activate()

guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
    recordResult(1, message: "PASS: daemon rejected the unauthorized client.")
}) as? LidSwitchDaemonXPCProtocol else {
    fputs("PASS: unauthorized client could not create an XPC proxy.\n", stdout)
    exit(0)
}

proxy.checkVersion { version in
    recordResult(2, message: "FAIL: unauthorized client reached daemon: \(version)")
}

let waitResult = semaphore.wait(timeout: .now() + 5)
lock.lock()
let finalResult = result
lock.unlock()
connection.invalidate()
if waitResult == .timedOut || finalResult == 0 {
    fputs("FAIL: timed out without an explicit rejection. Is the daemon enabled?\n", stderr)
    exit(2)
}
exit(finalResult == 1 ? 0 : 1)
