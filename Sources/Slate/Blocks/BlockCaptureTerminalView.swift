@preconcurrency import SwiftTerm
import Darwin

final class BlockCaptureTerminalView: LocalProcessTerminalView {
    var onDataReceived: ((ArraySlice<UInt8>) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        onDataReceived?(slice)
        super.dataReceived(slice: slice)
    }

    override func getWindowSize() -> winsize {
        var size = super.getWindowSize()
        if size.ws_row == 0 {
            size.ws_row = 24
        }
        if size.ws_col == 0 {
            size.ws_col = 80
        }
        if size.ws_xpixel == 0 {
            size.ws_xpixel = 640
        }
        if size.ws_ypixel == 0 {
            size.ws_ypixel = 384
        }
        return size
    }
}
