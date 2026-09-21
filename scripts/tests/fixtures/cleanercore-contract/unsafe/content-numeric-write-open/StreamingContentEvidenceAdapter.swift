import CleanerCore
import CryptoKit
import Darwin
import Foundation

func openWithNumericWriteAuthority(_ path: UnsafePointer<CChar>) -> Int32 {
    open(path, 1)
}
