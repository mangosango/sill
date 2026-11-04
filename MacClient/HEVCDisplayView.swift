import AppKit
import AVFoundation
import CoreMedia
import StreamProtocol

/// AppKit surface and pointer adapted from Alexander Deutsch's PR #128 (173843be).
/// Sample handling, blanking and recovery follow the current iPad renderer.
/// The Mac's counterpart of the iOS client's HEVCDisplayView, with the same interface StreamClient
/// drives (`apply`, `enqueue`, `clear`, `onVideoSize`, the pointer sprite): an NSView backed by an
/// AVSampleBufferDisplayLayer, which decodes HEVC in hardware itself.
///
/// The pointer sprite shows the streamed Mac's own pointer while that Mac (or another device) moves
/// it, where kind 26 says it is. The native input attachment must use the streamed cursor shape
/// for this Mac's system cursor; this sprite is only the remote pointer.
final class HEVCDisplayView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()

    private var formatDescription: CMVideoFormatDescription?
    private var waitingForKeyframe = true
    private var lastParameterSets: Data?

    /// The streamed frame's pixel size, reported on main whenever new parameter sets arrive.
    var onVideoSize: ((CGSize) -> Void)?
    /// The same event for the pointer (`StreamClient.pointerFrameChanged`), as on iOS.
    var onVideoSizeForPointer: ((CGSize) -> Void)?

    /// The queue `apply` and `enqueue` run on (the client's network queue): the layer's own
    /// notifications, which come on whatever thread AVFoundation posts them, are looked at there.
    var renderQueue: DispatchQueue?
    /// The picture was interrupted: the layer was flushed and waits for a keyframe (`checkLayer`),
    /// which a still window on the Mac never sends by itself. The client asks for one
    /// (KeyframeRecovery). On `renderQueue`.
    var onNeedsKeyframe: (() -> Void)?
    /// A keyframe ended a wait: the picture is back (after an interruption, or a new source's first).
    /// When the layer still read interrupted at that keyframe, `checkLayer` throws it away with its
    /// flush and says so first, then `onNeedsKeyframe`: for the client the picture came back and was
    /// lost again at once, so it asks again, as for a repeat (KeyframeRecovery). On `renderQueue`.
    var onPictureBack: (() -> Void)?
    /// The layer's notifications (`observeLayer`).
    private var layerObservers: [NSObjectProtocol] = []
    /// When a keyframe last ended a wait (`CACurrentMediaTime`): a decode failure posted before then
    /// is about a frame from before the picture came back. On `renderQueue`.
    private var resumedAt: CFTimeInterval = 0

    private let cursorLayer = HEVCDisplayView.makeCursorLayer()
    /// Where the sprite's tip is, a fraction of the video frame, or nil when hidden.
    private var pointer: CGPoint?
    /// Main-thread copy of the frame size the layer draws; zero hides the sprite.
    private var pointerVideoSize: CGSize = .zero

    /// Where `resizeAspect` draws a `videoSize` frame inside `bounds` (the letterboxed rect), which
    /// is what maps the mouse to a fraction of the frame. `.zero` while the video size is unknown.
    static func videoRect(in bounds: CGRect, videoSize: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(x: bounds.minX + (bounds.width - size.width) / 2,
                      y: bounds.minY + (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = bounds
        layer?.addSublayer(displayLayer)
        layer?.addSublayer(cursorLayer)
        observeLayer()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Top-left origin, like the video and like the fractions the protocol speaks.
    override var isFlipped: Bool { true }

    /// The native input attachment, not the video, owns mouse events.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
        placeCursor()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor { cursorLayer.contentsScale = scale }
    }

    // MARK: The pointer sprite

    /// Shows the sprite at `p` (a fraction of the video frame) or hides it (nil). Main thread.
    func setPointer(_ p: CGPoint?) {
        pointer = p
        placeCursor()
    }

    /// The streamed Mac's cursor image with its hotspot at the layer's anchor, or the built-in arrow
    /// when nil. Sizes are Mac points, drawn 1:1 in this Mac's points. Main thread.
    func setCursorShape(_ shape: StreamClient.CursorShape?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let shape, let cg = shape.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           shape.size.width > 0, shape.size.height > 0 {
            cursorLayer.path = nil
            cursorLayer.shadowPath = nil
            cursorLayer.shadowOpacity = 0
            cursorLayer.contents = cg
            cursorLayer.contentsGravity = .resize
            cursorLayer.bounds = CGRect(origin: .zero, size: shape.size)
            cursorLayer.anchorPoint = CGPoint(x: shape.hotspot.x / shape.size.width, y: shape.hotspot.y / shape.size.height)
        } else {
            let arrow = Self.arrowPath
            cursorLayer.contents = nil
            cursorLayer.path = arrow
            cursorLayer.shadowPath = arrow
            cursorLayer.shadowOpacity = 0.3
            cursorLayer.bounds = arrow.boundingBox
            cursorLayer.anchorPoint = .zero
        }
        placeCursor()
    }

    /// The sprite's tip on the pointer inside the letterboxed video, never animated. The view is
    /// flipped, and AppKit flips its layer's geometry to match, so layer and view share coordinates.
    private func placeCursor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let rect = Self.videoRect(in: bounds, videoSize: pointerVideoSize)
        guard let p = pointer, rect.width > 0, rect.height > 0 else {
            cursorLayer.isHidden = true
            return
        }
        let x = min(max(p.x, 0), 1), y = min(max(p.y, 0), 1)
        cursorLayer.position = CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        cursorLayer.isHidden = false
    }

    /// The iOS client's arrow: white, a 1 pt black outline and a soft shadow, its tip the hotspot.
    static let arrowPath: CGPath = {
        let arrow = CGMutablePath()
        arrow.addLines(between: [
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 16.8), CGPoint(x: 4.0, y: 12.8), CGPoint(x: 6.8, y: 19.2),
            CGPoint(x: 9.6, y: 18.0), CGPoint(x: 6.9, y: 12.0), CGPoint(x: 12.0, y: 12.0),
        ])
        arrow.closeSubpath()
        return arrow
    }()

    private static func makeCursorLayer() -> CAShapeLayer {
        let arrow = arrowPath
        let shape = CAShapeLayer()
        shape.path = arrow
        shape.fillColor = NSColor.white.cgColor
        shape.strokeColor = NSColor.black.cgColor
        shape.lineWidth = 1
        shape.lineJoin = .round
        shape.bounds = arrow.boundingBox
        shape.anchorPoint = .zero
        shape.shadowPath = arrow
        shape.shadowColor = NSColor.black.cgColor
        shape.shadowOpacity = 0.3
        shape.shadowRadius = 1
        shape.shadowOffset = CGSize(width: 0, height: 1)
        shape.zPosition = 100
        shape.isHidden = true
        return shape
    }

    deinit { layerObservers.forEach(NotificationCenter.default.removeObserver) }

    /// The layer says it could not decode a frame, or that it needs a flush before it decodes again
    /// (iOS says so when Sill goes to the background, or another app takes the decoder): looked at on
    /// `renderQueue` at once, since a still window sends no frame that would show it (`checkLayer`).
    private func observeLayer() {
        let center = NotificationCenter.default
        layerObservers.append(center.addObserver(forName: .AVSampleBufferDisplayLayerFailedToDecode, object: displayLayer,
                                                 queue: nil) { [weak self] note in
            let error = note.userInfo?[AVSampleBufferDisplayLayerFailedToDecodeNotificationErrorKey] as? Error
            let postedAt = CACurrentMediaTime()
            self?.renderQueue?.async { [weak self] in
                // A frame enqueued before the picture came back failed: the flush that preceded the
                // keyframe already dealt with it, and acting now would throw the new picture away.
                guard let self, postedAt >= self.resumedAt else { return }
                self.checkLayer("(its notification)", failedToDecode: error)
            }
        })
        layerObservers.append(center.addObserver(forName: .AVSampleBufferDisplayLayerRequiresFlushToResumeDecodingDidChange,
                                                 object: displayLayer, queue: nil) { [weak self] _ in
            self?.renderQueue?.async { [weak self] in self?.checkLayer("(its notification)") }
        })
    }

    /// Thread-safe: AVSampleBufferDisplayLayer's enqueue/flush are documented as safe off main.
    func apply(_ ps: ParameterSets) {
        // The host repeats the parameter sets with every keyframe. Only a real change (a new source,
        // a resize) needs a new format description and a blank layer; a repeat must not flicker.
        let encoded = ps.encoded()
        if encoded == lastParameterSets, formatDescription != nil { return }
        lastParameterSets = encoded
        let buffers = ps.sets.map { set -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
            set.copyBytes(to: p, count: set.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        let pointers = buffers.map { UnsafePointer($0) }
        let sizes = ps.sets.map(\.count)

        var desc: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
            allocator: nil, parameterSetCount: pointers.count, parameterSetPointers: pointers,
            parameterSetSizes: sizes, nalUnitHeaderLength: Int32(ps.nalUnitHeaderLength),
            extensions: nil, formatDescriptionOut: &desc)
        guard status == noErr, let desc else { print("format description failed: \(status)"); return }
        formatDescription = desc
        waitingForKeyframe = true
        let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
        let size = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pointerVideoSize = size
            self.onVideoSize?(size)
            self.placeCursor()
            self.onVideoSizeForPointer?(size)
        }
        // Remove the last frame too: switching sources should show black until the new keyframe,
        // not the previous window frozen in place.
        displayLayer.flushAndRemoveImage()
    }

    /// A locked Mac (docs/locked-mac-plan.md): the picture removed at once, nothing shown until the next
    /// keyframe, the format kept. On `renderQueue` (the client's network queue), as `apply` and `enqueue`.
    func blank() {
        waitingForKeyframe = true
        displayLayer.flushAndRemoveImage()
    }

    /// Session over: drop the picture and forget the format so the next Mac starts clean.
    func clear() {
        formatDescription = nil
        lastParameterSets = nil
        waitingForKeyframe = true
        displayLayer.flushAndRemoveImage()
        // The pointer's copy of the size is main-thread state; the client zeroes its own alongside.
        DispatchQueue.main.async { [weak self] in
            self?.pointerVideoSize = .zero
            self?.placeCursor()
        }
    }

    func enqueue(_ data: Data, isKeyframe: Bool) {
        guard !data.isEmpty, let desc = formatDescription else { return }
        let resuming = waitingForKeyframe
        if waitingForKeyframe {
            guard isKeyframe else { return }
            waitingForKeyframe = false
        }

        let count = data.count
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: count, flags: 0,
                                                 blockBufferOut: &block) == noErr, let block,
              CMBlockBufferAssureBlockMemory(block) == noErr else { return }
        let replaced = data.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: count)
        }
        guard replaced == noErr else { return }

        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
        var size = count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: desc, sampleCount: 1,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size,
                                        sampleBufferOut: &sample) == noErr, let sample else { return }

        // Show each frame as soon as it decodes instead of scheduling by timestamp.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as NSArray?,
           let first = attachments.firstObject as? NSMutableDictionary {
            first[kCMSampleAttachmentKey_DisplayImmediately as String] = true
        }

        if checkLayer("at a frame", failedToDecode: nil, droppingKeyframe: resuming) { return }
        if resuming { resumedAt = CACurrentMediaTime() }
        displayLayer.enqueue(sample)
        if resuming {
            onPictureBack?()
        }
    }

    /// Whether the picture was interrupted: the layer failed (its `status`, with its `error`), could
    /// not decode a frame (`failedToDecode`, from its notification), or needs a flush before it
    /// decodes again (Sill was in the background, or another app took the decoder). If so the layer
    /// is flushed (it keeps the last image it showed), waits for a keyframe, and `onNeedsKeyframe` is
    /// told, since a still window on the Mac sends none. The Mac sends its parameter sets before
    /// every keyframe and every sample carries the format, so nothing else needs sending again. From
    /// each frame let through, the layer's notifications, and the picture's window becoming active
    /// (StreamClient). `droppingKeyframe`: the frame is the keyframe that ends the wait, which the
    /// flush throws away: `onPictureBack` is told first, so the client counts the picture back and
    /// lost again and asks again at a repeat's spacing (KeyframeRecovery), rather than taking the
    /// layer's word as part of an interruption whose keyframe already came. On `renderQueue`. True
    /// when it flushed.
    @discardableResult
    func checkLayer(_ why: String, failedToDecode: Error? = nil, droppingKeyframe: Bool = false) -> Bool {
        guard formatDescription != nil else { return false }    // no picture yet: nothing to lose
        let failed = displayLayer.status == .failed || displayLayer.error != nil
        let needsFlush = displayLayer.requiresFlushToResumeDecoding
        guard failed || needsFlush || failedToDecode != nil else { return false }
        displayLayer.flush()
        waitingForKeyframe = true
        if droppingKeyframe { onPictureBack?() }    // first: both reach the client in this order
        onNeedsKeyframe?()
        return true
    }

}
