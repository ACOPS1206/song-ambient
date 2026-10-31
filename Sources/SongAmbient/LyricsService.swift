import AppKit
import Foundation
import Combine
import AmbientCore
import CryptoKit
import UniformTypeIdentifiers

struct LyricRecord: Codable, Sendable, Identifiable {
    let id: Int
    let trackName: String, artistName: String
    let albumName: String?
    let duration: Double?
    let syncedLyrics: String?
    let lyricsfile: String?
    let hasWordSync: Bool?
    var selectedByUser:Bool?
}

private actor LyricsRepository {
    private var memory: [String:LyricRecord] = [:]
    private var lastRequest = Date.distantPast, blockedUntil = Date.distantPast
    private let folder: URL
    init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SongAmbient/Lyrics",isDirectory:true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    func find(title: String, artist: String, album: String, duration: Double, force: Bool) async throws -> LyricRecord? {
        let key = Self.cacheKey(title:title,artist:artist,album:album,duration:duration)
        let file = folder.appendingPathComponent(key+".json")
        if !force {
            if let cached = memory[key] { return cached }
            if let data = try? Data(contentsOf:file), let cached = try? JSONDecoder().decode(LyricRecord.self,from:data) { memory[key] = cached; return cached }
        }
        var query = [URLQueryItem(name:"track_name",value:title),.init(name:"artist_name",value:artist),.init(name:"album_name",value:album),.init(name:"duration",value:String(duration))]
        var direct: LyricRecord?
        if duration > 0, duration <= 3600 {
            if let data = try? await fetch(path:"get",query:query) { direct = try? JSONDecoder().decode(LyricRecord.self,from:data) }
            if let direct, direct.hasWordSync == true { try? save(direct,key:key,file:file); return direct }
        }
        try Task.checkCancellation()
        query.removeAll { $0.name == "duration" || $0.name == "album_name" }
        if let data = try? await fetch(path:"search",query:query), let records = try? JSONDecoder().decode([LyricRecord].self,from:data) {
            let exact = records.filter { Self.normalized($0.trackName) == Self.normalized(title) && Self.normalized($0.artistName) == Self.normalized(artist) && duration > 0 && $0.duration.map{abs($0-duration)<=2} == true }
            let ranked = exact.sorted {
                if ($0.hasWordSync == true) != ($1.hasWordSync == true) { return $0.hasWordSync == true }
                return Self.normalized($0.albumName ?? "") == Self.normalized(album) && Self.normalized($1.albumName ?? "") != Self.normalized(album)
            }
            if let first = ranked.first, first.hasWordSync == true || direct == nil { direct = first }
        }
        if let direct { try? save(direct,key:key,file:file) }
        return direct
    }
    private func save(_ record: LyricRecord,key: String,file: URL) throws { memory[key] = record; try JSONEncoder().encode(record).write(to:file,options:.atomic) }
    private static func cacheKey(title:String,artist:String,album:String,duration:Double)->String{
        SHA256.hash(data:Data("\(title)|\(artist)|\(album)|\(Int(duration.rounded()))".utf8)).map{String(format:"%02x",$0)}.joined()
    }
    func rememberSelection(_ selected:LyricRecord,title:String,artist:String,album:String,duration:Double){
        let key=Self.cacheKey(title:title,artist:artist,album:album,duration:duration)
        var record=selected;record.selectedByUser=true
        try? save(record,key:key,file:folder.appendingPathComponent(key+".json"))
    }
    func versions(title:String,artist:String,duration:Double) async throws->[LyricRecord]{
        let data=try await fetch(path:"search",query:[.init(name:"track_name",value:title),.init(name:"artist_name",value:artist)])
        return try JSONDecoder().decode([LyricRecord].self,from:data).filter{Self.normalized($0.trackName)==Self.normalized(title) && Self.normalized($0.artistName)==Self.normalized(artist) && ($0.syncedLyrics != nil || $0.lyricsfile != nil)}.sorted{
            if ($0.hasWordSync==true) != ($1.hasWordSync==true){return $0.hasWordSync==true}
            return abs(($0.duration ?? .infinity)-duration)<abs(($1.duration ?? .infinity)-duration)
        }
    }
    private func fetch(path: String, query: [URLQueryItem]) async throws -> Data {
        if blockedUntil > Date() { throw URLError(.resourceUnavailable) }
        let delay = 0.3-Date().timeIntervalSince(lastRequest)
        if delay > 0 { try await Task.sleep(for:.seconds(delay)) }
        try Task.checkCancellation(); lastRequest = Date()
        var components = URLComponents(string:"https://lrclib.net/api/\(path)")!; components.queryItems = query
        var request = URLRequest(url:components.url!,timeoutInterval:15)
        request.setValue("SongAmbient/2.1.1 (https://github.com/rachitkothadia/song-ambient)",forHTTPHeaderField:"User-Agent")
        let (data,response) = try await URLSession.shared.data(for:request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 429 { blockedUntil = Date().addingTimeInterval(Double(http.value(forHTTPHeaderField:"Retry-After") ?? "60") ?? 60); throw URLError(.resourceUnavailable) }
        guard http.statusCode == 200, data.count < 2_000_000 else { throw URLError(.badServerResponse) }
        return data
    }
    private static func normalized(_ text: String) -> String { text.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX")).split(whereSeparator:\.isWhitespace).joined(separator:" ") }
}

@MainActor final class LyricsService: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var words: [LyricWord] = []
    @Published private(set) var presentation=WordPresentation(lines:[])
    @Published private(set) var loading = false
    @Published private(set) var status = "Waiting for a song"
    @Published private(set) var provenance = ""
    @Published private(set) var timing = "No timing"
    @Published private(set) var versions:[LyricRecord]=[]
    @Published private(set) var findingVersions=false
    @Published private(set) var versionStatus=""
    private let repository = LyricsRepository()
    private var task: Task<Void,Never>?
    private var identity = ""
    private var versionTask:Task<Void,Never>?
    func clear() { task?.cancel(); lines=[];words=[];presentation=WordPresentation(lines:[]);loading=false;identity="";provenance="";timing="No timing";status="Waiting for a song" }
    func load(music: MusicWatcher, force: Bool = false) {
        guard !music.identity.isEmpty, force || identity != music.identity else { return }
        task?.cancel(); identity=music.identity
        let expected=identity,title=music.title,artist=music.artist,album=music.album,duration=music.catalogDuration
        loading=true;status="Finding timed lyrics…"
        task=Task {
            do {
                let record=try await repository.find(title:title,artist:artist,album:album,duration:duration,force:force)
                guard !Task.isCancelled, expected==identity else { return }
                guard let record else { loading=false;status="No matching synced lyrics. Import a timed Lyricsfile or LRC."; return }
                let rich = record.lyricsfile.flatMap { try? LyricsParser.parseLyricsfile($0) } ?? []
                let parsed = rich.isEmpty ? LyricsParser.parse(record.syncedLyrics ?? "") : rich
                install(parsed,provenance:record.selectedByUser == true ? "LRCLIB · saved recording \(record.id)":"LRCLIB · record \(record.id)")
                if record.selectedByUser == true,let length=record.duration,abs(length-duration)>2{status += " · Selected recording length differs; verify offset."}
            } catch {
                if !Task.isCancelled, expected==identity { status="Lyrics unavailable. Retry or import a timed file." }
            }
            if expected==identity { loading=false }
        }
    }
    private func install(_ parsed: [LyricLine], provenance: String) {
        lines=parsed.map { LyricLine(time:$0.time,end:$0.end,text:Hinglish.render($0.text),id:$0.id,words:$0.words.map{LyricWord(time:$0.time,end:$0.end,text:Hinglish.render($0.text),id:$0.id)}) }
        words=LyricTimeline.words(in:parsed).map { LyricWord(time:$0.time,end:$0.end,text:Hinglish.render($0.text),id:$0.id) }
        self.provenance=provenance
        presentation=WordPresentation(lines:lines,seed:UInt64.random(in:1...UInt64.max))
        timing=presentation.tokens.isEmpty ? "No lyrics":presentation.hasEstimatedWords ? "Word motion · estimated" : "Word sync"
        status=parsed.isEmpty ? "No timed lyrics in this file" : presentation.hasEstimatedWords ? "Individual words · estimated pacing from line timing. Import word cues for exact sync." : "\(words.count) timed words · Hinglish display"
    }
    func importFile(for music: MusicWatcher) {
        let panel=NSOpenPanel();panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
        panel.allowedContentTypes=[UTType(filenameExtension:"lrc"),UTType(filenameExtension:"yaml"),UTType(filenameExtension:"yml"),UTType(filenameExtension:"lyricsfile")].compactMap{$0}
        panel.message="Import word-timed Lyricsfile YAML or enhanced LRC. Existing timestamps are preserved."
        guard panel.runModal() == .OK,let url=panel.url else{return}
        let accessed=url.startAccessingSecurityScopedResource();defer{if accessed{url.stopAccessingSecurityScopedResource()}}
        do {
            let data=try Data(contentsOf:url);guard data.count<2_000_000,let text=String(data:data,encoding:.utf8) else{status="The lyric file is too large or isn't UTF-8.";return}
            let parsed:[LyricLine]
            if url.pathExtension.lowercased()=="lrc" { parsed=LyricsParser.parse(text) } else { parsed=try LyricsParser.parseLyricsfile(text) }
            guard !parsed.isEmpty else{status="This file has no valid timestamps.";return}
            task?.cancel();identity=music.identity;loading=false;install(parsed,provenance:"Imported · \(url.lastPathComponent)")
        }catch{status="Could not read the timed lyric file: \(error.localizedDescription)"}
    }
    func findVersions(music:MusicWatcher,titleOverride:String?=nil,artistOverride:String?=nil){
        versionTask?.cancel();versions=[];findingVersions=true;versionStatus="Finding recordings…"
        let title=titleOverride ?? music.title,artist=artistOverride ?? music.artist,duration=music.catalogDuration,expected=music.identity
        versionTask=Task{
            do{
                let results=try await repository.versions(title:title,artist:artist,duration:duration)
                guard !Task.isCancelled,music.identity==expected else{findingVersions=false;return}
                versions=results;versionStatus=results.isEmpty ? "No synced recordings found. You can import a timed file.":"Check the recording length before selecting. A different edit can have different timing."
            }catch{if !Task.isCancelled{versionStatus="Could not load recordings. Try again or import a timed file."}}
            findingVersions=false
        }
    }
    func choose(_ record:LyricRecord,music:MusicWatcher){
        let rich=record.lyricsfile.flatMap{try? LyricsParser.parseLyricsfile($0)} ?? []
        let parsed=rich.isEmpty ? LyricsParser.parse(record.syncedLyrics ?? ""):rich
        task?.cancel();loading=false;identity=music.identity
        install(parsed,provenance:"LRCLIB · manually selected recording \(record.id)")
        let title=music.title,artist=music.artist,album=music.album,duration=music.catalogDuration
        Task{await repository.rememberSelection(record,title:title,artist:artist,album:album,duration:duration)}
        if let duration=record.duration,abs(duration-music.catalogDuration)>2{status += " · Recording length differs; verify sync and adjust offset."}
    }
    nonisolated static func parse(_ lrc:String)->[LyricLine]{LyricsParser.parse(lrc)}
}
