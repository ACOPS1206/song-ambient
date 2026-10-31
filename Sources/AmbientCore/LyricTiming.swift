import Foundation
import Yams

public struct LyricWord: Identifiable, Equatable, Codable, Sendable {
    public let time: Double
    public let end: Double?
    public let text: String
    public let id: Int
    public init(time: Double, end: Double? = nil, text: String, id: Int) { self.time = time; self.end = end; self.text = text; self.id = id }
}
public struct LyricLine: Identifiable, Equatable, Codable, Sendable {
    public let time: Double
    public let end: Double?
    public let text: String
    public let id: Int
    public let words: [LyricWord]
    public init(time: Double, end: Double? = nil, text: String, id: Int, words: [LyricWord] = []) {
        self.time = time; self.end = end; self.text = text; self.id = id; self.words = words
    }
}
public enum Hinglish {
    public static func render(_ text: String) -> String {
        var output = "", run = "", inDevanagari = false
        func flush() {
            guard !run.isEmpty else { return }
            if inDevanagari {
                let latin = run.applyingTransform(StringTransform("Devanagari-Latin"), reverse: false) ?? run
                var roman=latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
                let scalars=run.unicodeScalars.map(\.value)
                let consonants=scalars.filter{(0x0915...0x0939).contains($0) || (0x0958...0x095F).contains($0)}
                if let last=scalars.last,consonants.count>1,((0x0915...0x0939).contains(last) || (0x0958...0x095F).contains(last)),roman.hasSuffix("a"){roman.removeLast()}
                if let last=scalars.last,(last==0x0901 || last==0x0902),roman.hasSuffix("m"){roman.removeLast();roman.append("n")}
                output += roman
            } else { output += run }
            run = ""
        }
        for scalar in text.unicodeScalars {
            let deva = (0x0900...0x097F).contains(scalar.value) || (0xA8E0...0xA8FF).contains(scalar.value)
            if deva != inDevanagari { flush(); inDevanagari = deva }
            run.unicodeScalars.append(scalar)
        }
        flush(); return output
    }
}
public enum LyricsParser {
    private static let stamps = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
    private static let wordStamps = try! NSRegularExpression(pattern: #"<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>"#)
    private static let offsets = try! NSRegularExpression(pattern: #"\[offset:\s*([+-]?\d+)\]"#)
    public static func parse(_ lrc: String) -> [LyricLine] {
        guard lrc.utf8.count < 2_000_000 else { return [] }
        let full = lrc as NSString
        let offset = offsets.firstMatch(in: lrc, range: NSRange(location: 0, length: full.length)).flatMap { Double(full.substring(with: $0.range(at: 1))) } ?? 0
        var rows: [(Double, String, [LyricWord])] = []
        for row in lrc.components(separatedBy: .newlines) {
            let ns = row as NSString, range = NSRange(location: 0, length: (row as NSString).length)
            let lineMatches = stamps.matches(in: row, range: range), matches = wordStamps.matches(in: row, range: range)
            var words: [LyricWord] = []
            for (index, match) in matches.enumerated() {
                let start = NSMaxRange(match.range), next = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
                let text = ns.substring(with: NSRange(location: start, length: max(0, next - start))).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                let end = index + 1 < matches.count ? timestamp(matches[index + 1], ns: ns) + offset / 1000 : nil
                words.append(LyricWord(time: max(0, timestamp(match, ns: ns) + offset / 1000), end: end.map { max(0, $0) }, text: text, id: words.count))
            }
            if !words.isEmpty {
                let time = lineMatches.first.map { max(0, timestamp($0, ns: ns) + offset / 1000) } ?? words[0].time
                rows.append((time, words.map(\.text).joined(separator: " "), words))
            } else if let last = lineMatches.last {
                let text = ns.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
                for match in lineMatches { rows.append((max(0, timestamp(match, ns: ns) + offset / 1000), text, [])) }
            }
        }
        return rows.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(time: $1.0, text: $1.1, id: $0, words: $1.2) }
    }
    public static func parseLyricsfile(_ yaml: String) throws -> [LyricLine] {
        guard yaml.utf8.count < 2_000_000 else { return [] }
        let document = try YAMLDecoder().decode(Lyricsfile.self, from: yaml)
        guard document.metadata?.offset_ms ?? 0 == 0 else { throw TimingError.unsupportedOffset }
        return document.lines.compactMap { line -> (Double, Double?, String, [LyricWord])? in
            let words = (line.words ?? []).filter { $0.start_ms != nil && $0.start_ms!.isFinite && $0.start_ms! >= 0 }
                .sorted { $0.start_ms! < $1.start_ms! }.enumerated().map { index, word in
                    LyricWord(time: word.start_ms! / 1000, end: word.end_ms.flatMap { $0 >= word.start_ms! && $0.isFinite ? $0 / 1000 : nil }, text: word.text, id: index)
                }
            guard let start = line.start_ms ?? words.first.map({ $0.time * 1000 }), start.isFinite, start >= 0 else { return nil }
            return (start / 1000, line.end_ms.flatMap { $0.isFinite && $0 >= start ? $0 / 1000 : nil }, line.text, words)
        }.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(time: $1.0, end: $1.1, text: $1.2, id: $0, words: $1.3) }
    }
    private static func timestamp(_ match: NSTextCheckingResult, ns: NSString) -> Double {
        let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0, seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
        let fraction = match.range(at: 3).location == NSNotFound ? "" : ns.substring(with: match.range(at: 3))
        return minutes * 60 + seconds + (fraction.isEmpty ? 0 : (Double(fraction) ?? 0) / pow(10, Double(fraction.count)))
    }
    public enum TimingError: LocalizedError { case unsupportedOffset
        public var errorDescription:String? { "This Lyricsfile uses an offset whose direction is not defined by the format. Export absolute timestamps or use enhanced LRC." }
    }
    private struct Lyricsfile: Decodable { let metadata:Metadata?;let lines: [Row] }
    private struct Metadata:Decodable { let offset_ms:Double? }
    private struct Row: Decodable { let text: String; let start_ms: Double?; let end_ms: Double?; let words: [Word]? }
    private struct Word: Decodable { let text: String; let start_ms: Double?; let end_ms: Double? }
}
public enum LyricTimeline {
    public static func words(in lines: [LyricLine]) -> [LyricWord] {
        lines.flatMap(\.words).sorted { $0.time < $1.time }.enumerated().map { LyricWord(time: $1.time, end: $1.end, text: $1.text, id: $0) }
    }
    public static func activeWord(in words: [LyricWord], at time: Double) -> Int? {
        guard let index = words.lastIndex(where: { $0.time <= time }) else { return nil }
        if let end = words[index].end, time > end { return nil }
        return index
    }
}
