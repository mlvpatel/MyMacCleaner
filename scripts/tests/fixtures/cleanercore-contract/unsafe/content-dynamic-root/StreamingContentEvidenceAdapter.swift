import CleanerCore
import CryptoKit
import Darwin
import Foundation

struct DynamicRootContentAdapterFixture {
    let volumes = FileManager().mountedVolumeURLs(
        includingResourceValuesForKeys: nil,
        options: []
    )
}
