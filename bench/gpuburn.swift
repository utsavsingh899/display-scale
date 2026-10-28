// gpuburn: keep the GPU at full load for some seconds and report how much work it did.
// It stands in for heavy GPU work such as Resolve effects or an export.
//
//   gpuburn <seconds>    print the work rate (GFLOP/s)
//
// Build: swiftc -O gpuburn.swift -o gpuburn

import Foundation
import Metal

let seconds = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 15
let threads = 4 << 20
let loops: Int32 = 2048

let source = """
#include <metal_stdlib>
using namespace metal;
kernel void burn(device float *out [[buffer(0)]], constant int &loops [[buffer(1)]],
                 uint id [[thread_position_in_grid]]) {
    float a = float(id) * 1e-7, b = 1.0001, c = 0.5, d = 0.25;
    for (int i = 0; i < loops; i++) {
        a = fma(a, b, 1e-4); b = fma(b, 0.9999, 1e-5);
        c = fma(c, d, 1e-4); d = fma(d, 0.9999, 1e-5);
    }
    out[id] = a + b + c + d;
}
"""

let device = MTLCreateSystemDefaultDevice()!
let library = try! device.makeLibrary(source: source, options: nil)
let pipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "burn")!)
let queue = device.makeCommandQueue()!
let output = device.makeBuffer(length: threads * 4, options: .storageModePrivate)!
var loopCount = loops

let inFlight = DispatchSemaphore(value: 3)
let lock = NSLock()
var completed = 0
let start = Date()
while Date().timeIntervalSince(start) < seconds {
    inFlight.wait()
    let buffer = queue.makeCommandBuffer()!
    let encoder = buffer.makeComputeCommandEncoder()!
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(output, offset: 0, index: 0)
    encoder.setBytes(&loopCount, length: 4, index: 1)
    encoder.dispatchThreads(MTLSize(width: threads, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: pipeline.threadExecutionWidth * 8, height: 1, depth: 1))
    encoder.endEncoding()
    buffer.addCompletedHandler { _ in
        lock.lock(); completed += 1; lock.unlock()
        inFlight.signal()
    }
    buffer.commit()
}
let last = queue.makeCommandBuffer()!
last.commit()
last.waitUntilCompleted()
let elapsed = Date().timeIntervalSince(start)
// Each loop does 4 fused multiply-adds (8 floating-point operations) for each thread.
let gflops = Double(completed) * Double(threads) * Double(loops) * 8 / elapsed / 1e9
print(String(format: "%.0f", gflops))
