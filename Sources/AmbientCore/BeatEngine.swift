import Foundation

public struct AudioFeatures: Equatable, Sendable {
    public var level = 0.0, bass = 0.0, mid = 0.0, treble = 0.0, onset = 0.0, beatStrength = 0.0
    public var beatIndex = 0
    public var bands = [Double](repeating: 0, count: 16)
    public init() {}
}
public struct BeatEngine {
    private var sub = 0.0, low = 0.0, body = 0.0
    private var bassBaseline = 0.001, previousBass = 0.0
    private var lastBeat = -Double.infinity, lastTime: Double?
    private var current = AudioFeatures()
    public init() {}
    public mutating func analyze(_ samples: [Float], sampleRate: Double, time: Double) -> AudioFeatures {
        guard !samples.isEmpty, sampleRate > 0 else { return current }
        let duration = Double(samples.count) / sampleRate
        let dt = min(0.1, max(0.0001, lastTime.map { time - $0 } ?? duration)); lastTime = time
        let aSub = 1 - exp(-2 * .pi * 35 / sampleRate), aLow = 1 - exp(-2 * .pi * 190 / sampleRate), aBody = 1 - exp(-2 * .pi * 2200 / sampleRate)
        var total = 0.0, bassPower = 0.0, midPower = 0.0, highPower = 0.0
        for value in samples {
            let x = Double(value)
            sub += aSub * (x - sub); low += aLow * (x - low); body += aBody * (x - body)
            total += x*x; bassPower += (low-sub)*(low-sub); midPower += (body-low)*(body-low); highPower += (x-body)*(x-body)
        }
        let rms = sqrt(total / Double(samples.count)), bass = sqrt(bassPower / Double(samples.count))
        let mid = sqrt(midPower / Double(samples.count)), high = sqrt(highPower / Double(samples.count))
        let contrast = max(0, bass - bassBaseline * 1.3) / max(0.004, bassBaseline)
        let rising = max(0, bass - previousBass) / max(0.003, bassBaseline)
        let onset = min(1, contrast * 0.55 + rising * 0.45)
        if rms > 0.004, bass > 0.003, onset > 0.28, rising > 0.05, time - lastBeat > 0.18 {
            current.beatIndex += 1; lastBeat = time
            current.beatStrength = min(1, (1-exp(-bass*18)) * 0.65 + onset*0.35)
        }
        bassBaseline += (1-exp(-dt/0.75)) * (bass-bassBaseline); previousBass = bass
        current.level = envelope(current.level, 1-exp(-rms*9), dt: dt, release: 0.2)
        current.bass = envelope(current.bass, 1-exp(-bass*20), dt: dt, release: 0.22)
        current.mid = envelope(current.mid, 1-exp(-mid*10), dt: dt, release: 0.14)
        current.treble = envelope(current.treble, 1-exp(-high*12), dt: dt, release: 0.08)
        current.onset = max(onset, current.onset * exp(-dt/0.085))
        return current
    }
    private func envelope(_ old: Double, _ target: Double, dt: Double, release: Double) -> Double {
        let value = old + (1-exp(-dt/(target > old ? 0.012 : release))) * (target-old)
        return value < 0.0001 ? 0 : min(1,value)
    }
}
public struct BounceSpring {
    public private(set) var value = 0.0
    private var velocity = 0.0
    public init() {}
    public mutating func impulse(_ amount: Double) { velocity += min(1.5,max(0,amount)) * 8 }
    public mutating func step(delta: Double, target: Double) -> Double {
        let dt = min(1.0/30,max(0,delta))
        velocity += (78*(target-value)-9.5*velocity)*dt; value += velocity*dt
        value = min(2,max(-0.25,value)); return value
    }
}
