import CleanerCore
import Darwin
import Dispatch
import Foundation

func observeOnly() {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    _ = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
    _ = DispatchTime.now().uptimeNanoseconds
    _ = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
}
