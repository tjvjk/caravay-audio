import Darwin
import Foundation
import Testing

private final class BundleLocator: NSObject {}

private struct Event: Encodable {
  enum CodingKeys: String, CodingKey {
    case type, channels, samples
    case sampleRate = "sample_rate"
  }

  let type: String
  var sampleRate: Int?
  var channels: Int?
  var samples: [Float]?

  static func audio(_ samples: [Float], rate: Int = 16_000, channels: Int = 1) -> Self {
    Self(type: "audio", sampleRate: rate, channels: channels, samples: samples)
  }
}

private struct Result {
  let status: Int32
  let output: Data
  let diagnostics: String

  func matches(_ expected: [Float]) -> Bool {
    let actual = samples
    return actual.count == expected.count
      && zip(actual, expected).allSatisfy { abs($0 - $1) <= max(1e-12, abs($1) * 1e-6) }
  }

  var samples: [Float] {
    stride(from: 0, to: output.count - output.count % 4, by: 4).map { offset in
      let bits = output.withUnsafeBytes {
        $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
      }
      return Float(bitPattern: UInt32(littleEndian: bits))
    }
  }
}

private final class Drain: @unchecked Sendable {
  private let completed = DispatchSemaphore(value: 0)
  private var data = Data()

  init(_ handle: FileHandle) {
    Thread.detachNewThread {
      self.data = handle.readDataToEndOfFile()
      try? handle.close()
      self.completed.signal()
    }
  }

  func collect() throws -> Data {
    try #require(completed.wait(timeout: .now() + 10) == .success, "Output drain timed out")
    return data
  }
}

private func invoke(
  _ events: [Event] = [], environment: [String: String] = [:],
  arguments: [String] = [], brokenPipe: Bool = false
) throws -> Result {
  let process = Process()
  process.executableURL = Bundle(for: BundleLocator.self).bundleURL
    .deletingLastPathComponent().appendingPathComponent("caravay-audio")
  var variables = ProcessInfo.processInfo.environment.filter {
    !$0.key.hasPrefix("CARAVAY_AUDIO_TEST_")
  }
  variables["CARAVAY_AUDIO_TEST_EVENTS"] = String(
    decoding: try JSONEncoder().encode(events), as: UTF8.self)
  variables.merge(environment) { _, new in new }
  process.environment = variables
  process.arguments = arguments
  let output = Pipe()
  let errors = Pipe()
  process.standardOutput = output
  process.standardError = errors
  defer {
    try? output.fileHandleForReading.close()
    try? output.fileHandleForWriting.close()
    try? errors.fileHandleForReading.close()
    try? errors.fileHandleForWriting.close()
  }
  if brokenPipe { try output.fileHandleForReading.close() }
  let completed = DispatchSemaphore(value: 0)
  process.terminationHandler = { _ in completed.signal() }
  try process.run()
  try output.fileHandleForWriting.close()
  try errors.fileHandleForWriting.close()
  let stdout = brokenPipe ? nil : Drain(output.fileHandleForReading)
  let stderr = Drain(errors.fileHandleForReading)
  let finished = completed.wait(timeout: .now() + 10) == .success
  if !finished {
    kill(process.processIdentifier, SIGKILL)
    _ = completed.wait(timeout: .now() + 5)
  }
  try #require(finished, "Capture process exceeded its timeout")
  return Result(
    status: process.terminationStatus, output: try stdout?.collect() ?? Data(),
    diagnostics: String(decoding: try stderr.collect(), as: UTF8.self))
}

@Test func stereoBecomesMonoWithoutDiagnosticsInPCM() throws {
  let result = try invoke([.audio([0.25, 0.75, -0.5, 0.5], channels: 2), Event(type: "eof")])
  #expect(result.status == 0)
  #expect(result.matches([0.5, 0]))
  #expect(result.output.count == 8)
  #expect(result.diagnostics == "capturing system audio; press Ctrl-C to stop\n")
}

@Test func successiveBuffersAreResampledInOrder() throws {
  let result = try invoke([
    .audio(Array(repeating: 0.25, count: 3_200), rate: 32_000),
    .audio(Array(repeating: 0.75, count: 3_200), rate: 32_000), Event(type: "eof"),
  ])
  #expect(result.status == 0)
  let samples = result.samples
  try #require(samples.count == 3_200)
  #expect(samples[100..<1_500].allSatisfy { abs($0 - 0.25) < 0.01 })
  #expect(samples[1_700..<3_100].allSatisfy { abs($0 - 0.75) < 0.01 })
}

@Test func permissionDenialLeavesOutputEmpty() throws {
  let result = try invoke([Event(type: "permission_denied")])
  #expect(result.status == 1)
  #expect(result.output.isEmpty)
  #expect(
    result.diagnostics == "permission_denied: allow Screen & System Audio Recording for "
      + "caravay-audio in System Settings > Privacy & Security, then retry\n")
}

@Test func fullQueueFailsInsteadOfDroppingSamples() throws {
  let result = try invoke(
    Array(repeating: .audio(Array(repeating: 0.25, count: 320)), count: 10)
      + [Event(type: "eof")],
    environment: [
      "CARAVAY_AUDIO_TEST_QUEUE_CAPACITY": "1", "CARAVAY_AUDIO_TEST_WRITE_DELAY_MS": "200",
    ])
  #expect(result.status == 1)
  #expect(result.diagnostics.hasSuffix("overload: stdout could not keep up with captured audio\n"))
}

@Test func streamFailurePreservesAcceptedPCM() throws {
  let result = try invoke([.audio([0.5, -0.5]), Event(type: "stream_failure")])
  #expect(result.status == 1)
  #expect(result.matches([0.5, -0.5]))
  #expect(
    result.diagnostics.hasSuffix("stream_failed: system audio capture stopped unexpectedly\n"))
}

@Test func closedDownstreamPipeReportsFailure() throws {
  let result = try invoke(
    Array(repeating: .audio(Array(repeating: 0.5, count: 8_000)), count: 8), brokenPipe: true)
  #expect(result.status == 1)
  #expect(result.diagnostics.hasSuffix("broken_pipe: downstream consumer closed the pipe\n"))
}

@Test func interruptionDrainsAcceptedPCM() throws {
  let result = try invoke([.audio([0.5, -0.5]), Event(type: "interruption")])
  #expect(result.status == 130)
  #expect(result.matches([0.5, -0.5]))
  #expect(result.diagnostics == "capturing system audio; press Ctrl-C to stop\n")
}

@Test func verboseCaptureIncludesTerminationMeasurements() throws {
  let result = try invoke(
    [.audio([0.5, -0.5]), Event(type: "interruption")], arguments: ["--verbose"])
  #expect(result.status == 130)
  #expect(result.diagnostics.contains("capture_queue_peak="))
  #expect(result.diagnostics.hasSuffix("interrupted: capture stopped by SIGINT\n"))
}

@Test func fragmentedWriteFailureIsReported() throws {
  let result = try invoke(
    [.audio([0.25, 0.5, 0.75, 1]), Event(type: "eof")],
    environment: [
      "CARAVAY_AUDIO_TEST_MAX_WRITE_BYTES": "3", "CARAVAY_AUDIO_TEST_FAIL_AFTER_WRITES": "2",
    ])
  #expect(result.status == 1)
  #expect(result.output.count == 6)
  #expect(result.diagnostics.hasSuffix("output_failed: PCM could not be written to stdout\n"))
}

@Test func eofRejectsLaterAudio() throws {
  let result = try invoke([Event(type: "eof"), .audio([0.75])])
  #expect(result.status == 0)
  #expect(result.output.isEmpty)
}

@Test func silenceDoesNotFabricateSamples() throws {
  let result = try invoke([Event(type: "silence"), .audio([0.75]), Event(type: "eof")])
  #expect(result.status == 0)
  #expect(result.matches([0.75]))
}

@Test func unavailableContentLeavesOutputEmpty() throws {
  let result = try invoke([Event(type: "content_unavailable")])
  #expect(result.status == 1)
  #expect(result.output.isEmpty)
  #expect(
    result.diagnostics == "capture_unavailable: ScreenCaptureKit found no display to capture\n")
}

@Test(arguments: ["--help", "--version"])
func informationDoesNotStartCapture(argument: String) throws {
  let result = try invoke([Event(type: "permission_denied")], arguments: [argument])
  #expect(result.status == 0)
  #expect(String(decoding: result.output, as: UTF8.self).contains("caravay-audio"))
  #expect(result.diagnostics.isEmpty)
}
