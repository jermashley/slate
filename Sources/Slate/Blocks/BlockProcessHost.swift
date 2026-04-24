import Darwin
import Foundation
@preconcurrency import SwiftTerm

final class BlockProcessHost: LocalProcessDelegate {
    var onDataReceived: ((ArraySlice<UInt8>) -> Void)?
    var onTerminated: ((Int32?) -> Void)?

    private(set) lazy var process = LocalProcess(delegate: self)

    var running: Bool {
        process.running
    }

    var shellPid: pid_t {
        process.shellPid
    }

    var childfd: Int32 {
        process.childfd
    }

    func start(
        executable: String,
        args: [String],
        environment: [String]?,
        execName: String?,
        currentDirectory: String?
    ) {
        process.startProcess(
            executable: executable,
            args: args,
            environment: environment,
            execName: execName,
            currentDirectory: currentDirectory
        )
    }

    func send(text: String) {
        let bytes = [UInt8](text.utf8)
        process.send(data: bytes[...])
    }

    func send(bytes: [UInt8]) {
        process.send(data: bytes[...])
    }

    func terminate() {
        process.terminate()
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        onTerminated?(exitCode)
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        onDataReceived?(slice)
    }

    func getWindowSize() -> winsize {
        winsize(ws_row: 24, ws_col: 80, ws_xpixel: 640, ws_ypixel: 384)
    }
}
