import Foundation

public enum SpotifyTimingSettings{
    public static func parseCrossfadeSeconds(_ preferences:String)->Double{
        var values:[String:String]=[:]
        for line in preferences.split(whereSeparator:\.isNewline){
            let pair=line.split(separator:"=",maxSplits:1).map(String.init)
            if pair.count==2{values[pair[0]]=pair[1]}
        }
        let enabled=values["audio.crossfade_v2"] ?? values["audio.crossfade"]
        let duration=values["audio.crossfade.time_v2"] ?? values["audio.crossfade.time"]
        guard enabled=="true",let duration,let milliseconds=Double(duration),milliseconds.isFinite,(0...12000).contains(milliseconds) else{return 0}
        return milliseconds/1000
    }
    public static func crossfadeSeconds()->Double{
        guard let support=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first else{return 0}
        let users=support.appendingPathComponent("Spotify/Users",isDirectory:true)
        let folders=(try? FileManager.default.contentsOfDirectory(at:users,includingPropertiesForKeys:nil)) ?? []
        let files=folders.filter{$0.lastPathComponent.hasSuffix("-user")}.map{$0.appendingPathComponent("prefs")}.filter{FileManager.default.fileExists(atPath:$0.path)}
        // With multiple profiles there is no safe public way to choose one.
        guard files.count==1,let text=try? String(contentsOf:files[0],encoding:.utf8) else{return 0}
        return parseCrossfadeSeconds(text)
    }
}
