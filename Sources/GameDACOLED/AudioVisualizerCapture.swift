import Accelerate
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class AudioVisualizerCapture: NSObject, @unchecked Sendable {
    enum Source {
        case systemAudio
        case microphone(String?)
    }

    private var stream: SCStream?
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let sampleQueue = DispatchQueue(label: "GameDACOLED.AudioVisualizer")
    private let barCount: Int
    private var smoothedLevels: [Float]
    private var sampleHistory: [Float]
    private var gain: Float = 0.7
    private let fftSize = 4096
    private let fftLog2N: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]
    var onLevels: (@Sendable ([Float]) -> Void)?

    init(barCount: Int = 12) {
        self.barCount = barCount
        self.smoothedLevels = Array(repeating: 0, count: barCount)
        self.sampleHistory = []
        self.fftLog2N = vDSP_Length(log2(Float(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(self.fftLog2N, FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: fftSize)
        self.windowed = [Float](repeating: 0, count: fftSize)
        self.realp = [Float](repeating: 0, count: fftSize / 2)
        self.imagp = [Float](repeating: 0, count: fftSize / 2)
        self.magnitudes = [Float](repeating: 0, count: fftSize / 2)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func start(source: Source, gain: Float) async throws {
        self.gain = gain
        await stop()

        switch source {
        case .systemAudio:
            try await startSystemAudio()
        case let .microphone(deviceID):
            try await ensureMicrophonePermission()
            try startMicrophone(deviceID: deviceID)
        }
    }

    func stop() async {
        guard let stream else {
            stopMicrophone()
            self.smoothedLevels = Array(repeating: 0, count: barCount)
            self.sampleHistory.removeAll(keepingCapacity: true)
            return
        }

        do {
            try await stream.stopCapture()
        } catch {
        }

        self.stream = nil
        stopMicrophone()
        self.smoothedLevels = Array(repeating: 0, count: barCount)
        self.sampleHistory.removeAll(keepingCapacity: true)
    }

    static func availableMicrophones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted {
                return
            }
            throw AppError("Microphone access was denied.")
        case .denied, .restricted:
            throw AppError("Microphone access is denied. Enable it in System Settings > Privacy & Security > Microphone.")
        @unknown default:
            throw AppError("Unable to determine microphone permission state.")
        }
    }

    private func startSystemAudio() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw AppError("No display found for system audio capture.")
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 1
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    private func startMicrophone(deviceID: String?) throws {
        let session = AVCaptureSession()
        session.beginConfiguration()

        let device = deviceID.flatMap { id in
            Self.availableMicrophones().first { $0.uniqueID == id }
        } ?? AVCaptureDevice.default(for: .audio)

        guard let device else {
            throw AppError("No microphone input device is available.")
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw AppError("Unable to attach microphone input.")
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        guard session.canAddOutput(output) else {
            throw AppError("Unable to attach microphone output.")
        }
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        session.addOutput(output)

        session.commitConfiguration()
        session.startRunning()

        self.captureSession = session
        self.audioOutput = output
    }

    private func stopMicrophone() {
        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
    }

    private func process(sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid else {
            return
        }

        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return
        }

        let streamDescription = streamDescriptionPointer.pointee

        var neededSize = 0
        var blockBuffer: CMBlockBuffer?

        let queryStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &neededSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )

        guard queryStatus == noErr, neededSize > 0 else {
            return
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: neededSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        let audioBufferListPointer = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &neededSize,
            bufferListOut: audioBufferListPointer,
            bufferListSize: neededSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            return
        }

        let bufferCount = Int(audioBufferListPointer.pointee.mNumberBuffers)
        guard bufferCount > 0 else {
            return
        }

        let samples = extractSamples(from: audioBufferListPointer, streamDescription: streamDescription)
        guard !samples.isEmpty else {
            return
        }

        sampleHistory.append(contentsOf: samples)
        let maxHistory = fftSize * 4
        if sampleHistory.count > maxHistory {
            sampleHistory.removeFirst(sampleHistory.count - maxHistory)
        }

        let levels = makeFrequencyLevels(
            from: sampleHistory,
            sampleRate: Float(streamDescription.mSampleRate),
            levelBoost: gain
        )
        onLevels?(levels)
    }

    private func extractSamples(
        from bufferListPointer: UnsafeMutablePointer<AudioBufferList>,
        streamDescription: AudioStreamBasicDescription
    ) -> [Float] {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        let formatFlags = streamDescription.mFormatFlags
        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        let channelsPerFrame = max(Int(streamDescription.mChannelsPerFrame), 1)
        var channelSamples: [[Float]] = []

        for buffer in buffers {
            guard let data = buffer.mData else {
                continue
            }

            let byteCount = Int(buffer.mDataByteSize)

            if isFloat && bitsPerChannel == 32 {
                let count = byteCount / MemoryLayout<Float>.size
                let pointer = data.bindMemory(to: Float.self, capacity: count)
                let raw = Array(UnsafeBufferPointer(start: pointer, count: count))
                if buffers.count == 1, channelsPerFrame > 1 {
                    channelSamples = deinterleaveInterleaved(raw, channelsPerFrame: channelsPerFrame)
                } else {
                    channelSamples.append(raw)
                }
                continue
            }

            if bitsPerChannel == 16 {
                let count = byteCount / MemoryLayout<Int16>.size
                let pointer = data.bindMemory(to: Int16.self, capacity: count)
                let raw = UnsafeBufferPointer(start: pointer, count: count).map { Float($0) / Float(Int16.max) }
                if buffers.count == 1, channelsPerFrame > 1 {
                    channelSamples = deinterleaveInterleaved(raw, channelsPerFrame: channelsPerFrame)
                } else {
                    channelSamples.append(raw)
                }
            }
        }

        return combineChannels(channelSamples)
    }

    private func makeFrequencyLevels(from samples: [Float], sampleRate: Float, levelBoost: Float) -> [Float] {
        guard samples.count >= fftSize else {
            return Array(repeating: 0.02, count: barCount)
        }

        let input = Array(samples.suffix(fftSize))
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        realp.withUnsafeMutableBufferPointer { realBuffer in
            imagp.withUnsafeMutableBufferPointer { imagBuffer in
                var splitComplex = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imagBuffer.baseAddress!
                )

                windowed.withUnsafeBufferPointer { windowedBuffer in
                    windowedBuffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPointer in
                        vDSP_ctoz(complexPointer, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                }

                vDSP_fft_zrip(fftSetup, &splitComplex, 1, fftLog2N, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        let nyquistBins = magnitudes.count
        let nyquistFrequency = sampleRate / 2
        let binWidth = sampleRate / Float(fftSize)
        var levels = Array(repeating: Float(0), count: barCount)
        let centers = visualizerBandCenters.map { min($0, nyquistFrequency * 0.98) }
        let edges = visualizerBandEdges(for: centers, nyquistFrequency: nyquistFrequency)

        for index in 0 ..< min(barCount, centers.count) {
            let startBin = max(1, Int(floor(edges[index] / binWidth)))
            let endBin = min(nyquistBins, max(startBin + 1, Int(ceil(edges[index + 1] / binWidth))))
            let clampedStart = min(startBin, nyquistBins - 1)
            let clampedEnd = min(max(endBin, clampedStart + 1), nyquistBins)
            let center = centers[index]
            let lowerEdge = edges[index]
            let upperEdge = edges[index + 1]
            let halfWidth = max((upperEdge - lowerEdge) * 0.5, binWidth)
            var weightedEnergy: Float = 0
            var totalWeight: Float = 0
            var peakEnergy: Float = 0

            for bin in clampedStart ..< clampedEnd {
                let frequency = Float(bin) * binWidth
                let distance = abs(frequency - center)
                let weight = max(0.15, 1 - distance / halfWidth)
                let energy = magnitudes[bin]
                weightedEnergy += energy * weight
                totalWeight += weight
                peakEnergy = max(peakEnergy, energy)
            }

            let averageEnergy = weightedEnergy / max(totalWeight, 1)
            let blendedEnergy = averageEnergy * 0.82 + peakEnergy * 0.18
            let amplitude = sqrtf(blendedEnergy)
            let bandProgress = Float(index) / Float(max(barCount - 1, 1))
            let bandGain = 1 + powf(bandProgress, 2.0) * 10
            let scaled = amplitude * bandGain * (0.0015 + levelBoost * 0.016)
            let normalized = min(1, powf(max(scaled, 0), 0.66))
            let boosted = min(1, normalized * (0.66 + levelBoost * 0.12))
            smoothedLevels[index] = max(boosted, smoothedLevels[index] * 0.84)
            levels[index] = smoothedLevels[index]
        }

        return levels
    }

    private var visualizerBandCenters: [Float] {
        [30, 40, 60, 100, 180, 340, 660, 1300, 2600, 5000, 10000, 16000]
    }

    private func visualizerBandEdges(for centers: [Float], nyquistFrequency: Float) -> [Float] {
        guard !centers.isEmpty else { return [20, nyquistFrequency] }

        var edges: [Float] = []
        edges.append(max(20, centers[0] * 0.75))

        for index in 0 ..< centers.count - 1 {
            edges.append(sqrtf(centers[index] * centers[index + 1]))
        }

        edges.append(min(nyquistFrequency * 0.98, centers.last! * 1.35))
        return edges
    }

    private func deinterleaveInterleaved(_ samples: [Float], channelsPerFrame: Int) -> [[Float]] {
        guard channelsPerFrame > 1 else {
            return [samples]
        }

        var channels = Array(repeating: [Float](), count: channelsPerFrame)
        let frameCount = samples.count / channelsPerFrame
        for frameIndex in 0 ..< frameCount {
            let base = frameIndex * channelsPerFrame
            for channelIndex in 0 ..< channelsPerFrame {
                channels[channelIndex].append(samples[base + channelIndex])
            }
        }
        return channels
    }

    private func combineChannels(_ channels: [[Float]]) -> [Float] {
        guard !channels.isEmpty else {
            return []
        }

        if channels.count == 1 {
            return channels[0]
        }

        let sampleCount = channels.map(\.count).min() ?? 0
        guard sampleCount > 0 else {
            return []
        }

        var combined = Array(repeating: Float(0), count: sampleCount)
        for index in 0 ..< sampleCount {
            let total = channels.reduce(Float(0)) { partial, channel in
                partial + channel[index]
            }
            combined[index] = total / Float(channels.count)
        }

        return combined
    }
}

extension AudioVisualizerCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else {
            return
        }

        process(sampleBuffer: sampleBuffer)
    }
}

extension AudioVisualizerCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        process(sampleBuffer: sampleBuffer)
    }
}
