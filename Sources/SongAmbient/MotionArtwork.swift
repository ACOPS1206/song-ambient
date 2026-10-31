import AppKit
import Foundation
import Combine

@MainActor final class MotionArtworkService: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var loading = false
    @Published private(set) var status = "Tap the artwork to look for an animated cover"
    private var task: Task<Void, Never>?
    func clear() { task?.cancel(); url = nil; loading = false; status = "Tap the artwork to look for an animated cover" }

    func load(music: MusicWatcher, storefront: String) {
        guard !music.identity.isEmpty, !loading else { return }
        let title = music.title, artist = music.artist, album = music.album
        loading = true
        task = Task {
            defer { loading = false }
            do {
                let country = storefront.lowercased().filter(\.isLetter)
                guard country.count == 2 else { status = "Enter a two-letter storefront, such as us"; return }
                var lookup = URLComponents(string: "https://itunes.apple.com/search")!
                lookup.queryItems = [.init(name: "term", value: "\(artist) \(album) \(title)"), .init(name: "entity", value: "song"), .init(name: "country", value: country), .init(name: "limit", value: "8")]
                let (data, _) = try await URLSession.shared.data(from: lookup.url!)
                let results = try JSONDecoder().decode(SearchResults.self, from: data).results
                guard let match = results.first(where: { $0.artistName.localizedCaseInsensitiveCompare(artist) == .orderedSame && $0.trackName.localizedCaseInsensitiveCompare(title) == .orderedSame }),
                      let page = URL(string: match.collectionViewUrl ?? match.trackViewUrl ?? ""), page.host == "music.apple.com" else { status = "No animated artwork found"; return }
                let (pageData, _) = try await URLSession.shared.data(from: page)
                guard !Task.isCancelled else { return }
                let html = String(decoding: pageData, as: UTF8.self).replacingOccurrences(of: #"\/"#, with: "/").replacingOccurrences(of: #"\u0026"#, with: "&")
                let pattern = #"https://[^\s"<>\\]+\.m3u8(?:\?[^\s"<>\\]*)?"#
                let regex = try NSRegularExpression(pattern: pattern)
                let ns = html as NSString
                let candidates = regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
                if let value = candidates.first(where: { $0.contains("video") || $0.contains("aod") }), let found = URL(string: value) {
                    url = found; status = "Animated artwork · Apple Music"
                } else { status = "No public animated artwork found for this album" }
            } catch { if !Task.isCancelled { status = "Could not load animated artwork" } }
        }
    }
    private struct SearchResults: Decodable { let results: [SearchTrack] }
    private struct SearchTrack: Decodable {
        let artistName: String
        let trackName: String
        let collectionViewUrl: String?
        let trackViewUrl: String?
    }
}
