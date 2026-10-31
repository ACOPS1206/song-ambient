import Foundation
import CoreAudio
import Accelerate
import Combine
import AmbientCore

final class AudioCapture: ObservableObject, @unchecked Sendable {
    @Published private(set) var running = false
    @Published private(set) var features = AudioFeatures()
    var level: Double { features.level }
    var bass: Double { features.bass }
    var beat: Int { features.beatIndex }
    var bands: [Double] { features.bands }
    @Published private(set) var status = "Spotify audio is off"
    private let queue = DispatchQueue(label: "local.songambient.audio", qos: .userInitiated)
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var format = AudioStreamBasicDescription()
    private var engine = BeatEngine()
    private var lastPublishedBeat = 0
    private var lastPublish = 0.0
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var requested = false
    private var processMonitor:DispatchSourceTimer?
    private var capturedProcesses:[AudioObjectID]=[]
    private var silencePublished = false
    private let fftSize = 512
    private var fft = vDSP_DFT_zop_CreateSetupD(nil, 512, .FORWARD)
    private var inputR = [Double](repeating: 0, count: 512)
    private var inputI = [Double](repeating: 0, count: 512)
    private var outputR = [Double](repeating: 0, count: 512)
    private var outputI = [Double](repeating: 0, count: 512)

    func start() {
        DispatchQueue.main.async { if !self.running { self.status="Starting Spotify audio…" } }
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.requested || self.aggregate == 0 else { return }
            self.requested = true
            self.installProcessMonitor()
            self.build()
            self.installOutputListener()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.requested = false
            self.processMonitor?.cancel();self.processMonitor=nil;self.capturedProcesses=[]
            self.tearDown()
            if let listener = self.outputListener {
                var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, self.queue, listener)
                self.outputListener = nil
            }
            DispatchQueue.main.async { self.running = false; self.features = AudioFeatures(); self.status = "Spotify audio is off" }
        }
    }

    private func build() {
        tearDown()
        let processes=spotifyProcesses()
        capturedProcesses=processes
        guard !processes.isEmpty else{DispatchQueue.main.async{self.running=false;self.features=AudioFeatures();self.status="Waiting for Spotify audio · other apps are excluded"};return}
        let description = CATapDescription(stereoMixdownOfProcesses:processes)
        description.name = "Song Ambient · Spotify Only"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var result = AudioHardwareCreateProcessTap(description, &tap)
        guard result == noErr else { fail("Allow System Audio Recording in System Settings to enable Music Sync.", result); return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        result = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
        guard result == noErr, format.mFormatID == kAudioFormatLinearPCM,
              format.mBitsPerChannel == 32, format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            fail("The output device did not provide 32-bit floating-point audio.", result); return
        }
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Song Ambient Audio Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
        ]
        result = AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate)
        guard result == noErr else { fail("Could not create the system audio tap.", result); return }
        result = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) { [weak self] _, input, _, _, _ in self?.process(input) }
        guard result == noErr else { fail("Could not listen to the audio output.", result); return }
        result = AudioDeviceStart(aggregate, ioProc)
        guard result == noErr else { fail("Could not start system audio.", result); return }
        DispatchQueue.main.async { self.running = true; self.status = "Listening to Spotify only · other apps are excluded" }
    }

    private func spotifyProcesses()->[AudioObjectID]{SpotifyProcessSelection.available().map(\.id)}
    private func installProcessMonitor(){
        guard processMonitor==nil else{return}
        let timer=DispatchSource.makeTimerSource(queue:queue)
        timer.schedule(deadline:.now()+1,repeating:1,leeway:.milliseconds(150))
        timer.setEventHandler{[weak self] in
            guard let self,self.requested else{return}
            if self.spotifyProcesses() != self.capturedProcesses{self.build()}
        }
        processMonitor=timer;timer.resume()
    }

    private func installOutputListener() {
        guard outputListener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.requested else { return }
            self.build()
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block) == noErr { outputListener = block }
    }

    private func process(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        let valid = buffers.filter { $0.mData != nil && $0.mDataByteSize > 0 }
        guard let frames = valid.map({ Int($0.mDataByteSize) / MemoryLayout<Float>.size / max(1,Int($0.mNumberChannels)) }).min() else { return }
        guard frames > 0 else { return }
        var mono = [Float](repeating:0,count:frames)
        for frame in 0..<frames {
            var strongest:Float=0
            for buffer in valid {
                let channels=max(1,Int(buffer.mNumberChannels)),samples=buffer.mData!.assumingMemoryBound(to:Float.self)
                for channel in 0..<channels { let sample=samples[frame*channels+channel];if abs(sample)>abs(strongest){strongest=sample} }
            }
            // Selecting the stronger channel avoids cancellation on antiphase
            // stereo and includes non-interleaved right-channel-only output.
            mono[frame]=strongest
            if frame < fftSize { inputR[frame]=Double(strongest)*(0.5-0.5*cos(2 * .pi * Double(frame)/Double(fftSize-1))) }
        }
        if frames < fftSize { for i in frames..<fftSize { inputR[i] = 0 } }
        let now=ProcessInfo.processInfo.systemUptime
        var snapshot=engine.analyze(mono,sampleRate:format.mSampleRate,time:now)
        if snapshot.level == 0 && snapshot.bass == 0 {
            guard !silencePublished else { return }
            silencePublished = true
            DispatchQueue.main.async { self.features=snapshot }
            return
        }
        silencePublished = false
        let hit=snapshot.beatIndex != lastPublishedBeat
        guard now - lastPublish >= 1.0 / 30 || hit else { return }
        lastPublish = now;lastPublishedBeat=snapshot.beatIndex
        var spectrum = [Double](repeating: 0, count: 16)
        if let fft {
            vDSP_DFT_ExecuteD(fft, inputR, inputI, &outputR, &outputI)
            for b in 0..<16 {
                let lo = max(1, Int(pow(256.0, Double(b) / 16)))
                let hi = min(255, max(lo + 1, Int(pow(256.0, Double(b + 1) / 16))))
                let energy = (lo..<hi).map { hypot(outputR[$0], outputI[$0]) }.max() ?? 0
                spectrum[b] = min(1, log1p(energy * 2) / 4)
            }
        }
        snapshot.bands=spectrum
        DispatchQueue.main.async { self.features=snapshot }
    }

    private func fail(_ message: String, _ code: OSStatus) {
        tearDown()
        DispatchQueue.main.async { self.running = false; self.status = "\(message) (\(code))" }
    }

    private func tearDown() {
        if let ioProc, aggregate != 0 { AudioDeviceStop(aggregate, ioProc); AudioDeviceDestroyIOProcID(aggregate, ioProc) }
        ioProc = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        engine=BeatEngine();lastPublishedBeat=0;silencePublished=false
    }
}
