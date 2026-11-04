import Foundation
import QuartzCore
import StreamProtocol

precondition(CommandLine.arguments.suffix(2) == ["-SillSoundSink", "manual"])
precondition(MacAudioDevice.duration(frames: 240, rate: 48_000) == 0.005)
for rate in [0.0, -1, .infinity, .nan] {
    precondition(MacAudioDevice.duration(frames: 240, rate: rate) == 0)
}
let encoder = try AudioEncoder(framesPerPacket: 480)
let output = AudioOutput(refresh: 1 / 60)
output.sessionStarted(away: false)
output.format(AudioFormat(codec: "aac-eld", sampleRate: 48_000, channels: 2,
                          framesPerPacket: 480, primingFrames: encoder.priming, epoch: 1, cookie: encoder.cookie))
for n in 0..<160 {
    let stamp = Date().timeIntervalSince1970
    output.frame(stamp: stamp, arrival: CACurrentMediaTime())
    let samples = (0..<960).map { Float(sin(Double($0 + n * 960) * 0.03) * 0.01) }
    let packet = encoder.encode(samples)!
    output.packets(AudioPackets(epoch: 1, seq: UInt32(n), segmentStart: n == 0, packets: [packet]), stamp: stamp)
    Thread.sleep(forTimeInterval: 0.01)
}
output.queue.sync {}
precondition(output.takeSecond() != nil, "real decoder/playout must schedule offline audio")
output.setMuted(true)
output.queue.sync {}
output.setMuted(false)
output.setSceneForeground(false)
output.setSceneForeground(true)
output.sessionEnded()
output.queue.sync {}
precondition(output.latestSecond == nil)
// Formats/packets after teardown must not restart output.
output.format(AudioFormat(epoch: 2))
output.packets(AudioPackets(epoch: 1, seq: 200, segmentStart: false, packets: [Data()]), stamp: 0)
output.queue.sync {}
precondition(output.latestSecond == nil)
print("mac-audio-output: offline decode/schedule, mute, visibility and teardown passed")
