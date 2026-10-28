// powermeter: measure the average GPU power without sudo.
//
//   powermeter <seconds>    print the average GPU power in mW
//
// The value comes from IOReport "GPU Energy" (the same data that powermetrics uses).
// On the M5 with macOS 27, IOReport gives 0 for CPU and DRAM energy without sudo,
// so bench.sh uses the WindowServer CPU time for the CPU side.
// Build: swiftc -O powermeter.swift -o powermeter

import Foundation

let lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)
func sym<T>(_ name: String, _: T.Type) -> T {
    guard let lib, let pointer = dlsym(lib, name) else { fatalError("IOReport: \(name) not found") }
    return unsafeBitCast(pointer, to: T.self)
}

typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
typealias CreateSubscription = @convention(c) (UnsafeRawPointer?, CFMutableDictionary,
    UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> OpaquePointer?
typealias CreateSamples = @convention(c) (OpaquePointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
typealias ChannelInteger = @convention(c) (CFDictionary, Int32) -> Int64

let copyChannels = sym("IOReportCopyChannelsInGroup", CopyChannelsInGroup.self)
let createSubscription = sym("IOReportCreateSubscription", CreateSubscription.self)
let createSamples = sym("IOReportCreateSamples", CreateSamples.self)
let createDelta = sym("IOReportCreateSamplesDelta", CreateSamplesDelta.self)
let channelName = sym("IOReportChannelGetChannelName", ChannelString.self)
let channelUnit = sym("IOReportChannelGetUnitLabel", ChannelString.self)
let channelValue = sym("IOReportSimpleGetIntegerValue", ChannelInteger.self)

guard let seconds = CommandLine.arguments.dropFirst().first.flatMap(Double.init), seconds > 0 else {
    FileHandle.standardError.write("usage: powermeter <seconds>\n".data(using: .utf8)!)
    exit(1)
}
guard let group = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else {
    fatalError("IOReport: no Energy Model channels")
}
let desired = CFDictionaryCreateMutableCopy(nil, 0, group)!
var subscribed: Unmanaged<CFMutableDictionary>?
guard let subscription = createSubscription(nil, desired, &subscribed, 0, nil), let subscribed else {
    fatalError("IOReport: cannot subscribe")
}
let channels = subscribed.takeRetainedValue()

let start = createSamples(subscription, channels, nil)!.takeRetainedValue()
let startTime = Date()
Thread.sleep(forTimeInterval: seconds)
let end = createSamples(subscription, channels, nil)!.takeRetainedValue()
let elapsed = Date().timeIntervalSince(startTime)

let delta = createDelta(start, end, nil)!.takeRetainedValue() as NSDictionary
var millijoules = 0.0
for item in delta["IOReportChannels"] as? [NSDictionary] ?? [] {
    let channel = item as CFDictionary
    guard channelName(channel)?.takeUnretainedValue() as String? == "GPU Energy" else { continue }
    let unit = (channelUnit(channel)?.takeUnretainedValue() as String? ?? "mJ").trimmingCharacters(in: .whitespaces)
    let scale = ["nJ": 1e-6, "uJ": 1e-3, "µJ": 1e-3, "mJ": 1.0][unit] ?? 1.0
    millijoules += Double(channelValue(channel, 0)) * scale
}
print(String(format: "%.0f", millijoules / elapsed))
