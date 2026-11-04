#!/bin/bash
# Native output compiled with the real shared decoder/playout; offline only, no HAL output opened.
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "$#" -ne 0 ]; then echo "mac-audio-output: no arguments supported" >&2; exit 2; fi
swiftc -emit-module -emit-library -module-name StreamProtocol Sources/StreamProtocol/*.swift -o "$out/libStreamProtocol.dylib"
swiftc -D DEBUG -I "$out" -L "$out" -lStreamProtocol -Xlinker -rpath -Xlinker "$out" \
    iOSClient/AudioOutput.swift iOSClient/AudioDecoder.swift iOSClient/AudioPlayout.swift \
    MacClient/MacAudioDevice.swift Sources/SillHost/AudioEncoder.swift "$here/main.swift" -o "$out/check"
"$out/check" -SillSoundSink manual
for mode in release debug; do
    flags=""
    if [ "$mode" = debug ]; then flags="-D DEBUG"; fi
    swiftc $flags -typecheck -I "$out" iOSClient/AudioOutput.swift iOSClient/AudioDecoder.swift \
        iOSClient/AudioPlayout.swift MacClient/MacAudioDevice.swift iOSClient/StreamClient+Audio.swift \
        "$here/StreamClientCompileStub.swift"
done
