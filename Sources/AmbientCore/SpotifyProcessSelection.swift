import CoreAudio
import Foundation

public struct SpotifyAudioProcess:Sendable{
    public let id:AudioObjectID
    public let bundleID:String
}
public enum SpotifyProcessSelection{
    public static func available()->[SpotifyAudioProcess]{
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyProcessObjectList,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var size:UInt32=0
        let system=AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system,&address,0,nil,&size)==noErr,size>0 else{return []}
        var objects=[AudioObjectID](repeating:0,count:Int(size)/MemoryLayout<AudioObjectID>.size)
        let status=objects.withUnsafeMutableBytes{AudioObjectGetPropertyData(system,&address,0,nil,&size,$0.baseAddress!)}
        guard status==noErr else{return []}
        return objects.compactMap{object in
            var property=AudioObjectPropertyAddress(mSelector:kAudioProcessPropertyBundleID,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            var value:Unmanaged<CFString>?,bytes=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(object,&property,0,nil,&bytes,&value)==noErr,let value else{return nil}
            let bundle=value.takeRetainedValue() as String
            return SpotifyAudioPolicy.includes(bundleID:bundle) ? SpotifyAudioProcess(id:object,bundleID:bundle):nil
        }.sorted{$0.id<$1.id}
    }
}
