# `mac-audio-output`

**Checks:** the Mac viewer's sound output, offline: the real AAC-ELD decoder and playout scheduling a
synthetic host's packets through manual rendering (`-SillSoundSink manual`, no device output opened),
mute and unmute, and the output device's duration arithmetic for bad rates.

**Compiles:** `iOSClient/AudioOutput.swift`, `AudioDecoder.swift`, `AudioPlayout.swift`, `PictureInPicturePolicy.swift`, `MacClient/MacAudioDevice.swift`,
`Sources/SillHost/AudioEncoder.swift` and `Sources/StreamProtocol`
