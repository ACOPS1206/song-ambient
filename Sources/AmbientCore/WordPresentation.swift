import Foundation

public struct DisplayWord:Identifiable,Equatable,Sendable{
    public let id:Int
    public let text:String
    public let lineID:Int
}
public struct WordPlaybackFrame:Sendable{
    public let index:Int?
    public let entrance:Double
    public let exact:Bool
}
public struct StarPoint:Equatable,Sendable{
    public let x:Double,y:Double
    public init(x:Double,y:Double){self.x=x;self.y=y}
    public func distance(to other:StarPoint)->Double{hypot(x-other.x,y-other.y)}
}
public enum ConstellationLayout{
    public static func positions(count:Int,seed:UInt64)->[StarPoint]{
        var state=seed,points:[StarPoint]=[]
        func random()->Double{
            state &+= 0x9e3779b97f4a7c15
            var value=state;value=(value^(value>>30)) &* 0xbf58476d1ce4e5b9
            value=(value^(value>>27)) &* 0x94d049bb133111eb
            return Double(value^(value>>31))/Double(UInt64.max)
        }
        for _ in 0..<max(0,count){
            var point=StarPoint(x:0.5,y:0.5)
            for _ in 0..<120{
                point=StarPoint(x:0.14+random()*0.72,y:0.23+random()*0.52)
                let previousDistance=points.last.map{$0.distance(to:point)} ?? 0.4
                if previousDistance>0.22 && previousDistance<0.72 && points.suffix(7).allSatisfy({$0.distance(to:point)>0.17}){break}
            }
            points.append(point)
        }
        return points
    }
}

/// Display pacing is deliberately separate from provider timestamps. A line
/// with no word cues can animate words, but is never represented as exact sync.
public struct WordPresentation:Sendable{
    private struct Segment:Sendable{
        let start:Double,end:Double?
        let range:Range<Int>
        let boundaries:[Double]
        let exact:Bool
    }
    public let tokens:[DisplayWord]
    public let stars:[StarPoint]
    public let hasEstimatedWords:Bool
    private let segments:[Segment]
    public init(lines:[LyricLine],seed:UInt64=0){
        var words:[DisplayWord]=[],groups:[Segment]=[],estimated=false
        for (lineIndex,line) in lines.enumerated(){
            let nextLine=lineIndex+1<lines.count ? lines[lineIndex+1].time:nil
            let lineEnd=line.end ?? nextLine
            let supplied=line.words.sorted{$0.time<$1.time}
            let parts:[(String,Double,Double?,Bool)]
            if supplied.isEmpty{parts=[(line.text,line.time,lineEnd,false)]}
            else{parts=supplied.enumerated().map{index,word in (word.text,word.time,word.end ?? (index+1<supplied.count ? supplied[index+1].time:lineEnd),true)}}
            for (text,start,end,provided) in parts{
                let split=text.split(whereSeparator:\.isWhitespace).map(String.init)
                let lower=words.count
                for text in split{words.append(DisplayWord(id:words.count,text:text,lineID:line.id))}
                let exact=provided && split.count==1
                if !split.isEmpty && !exact{estimated=true}
                let weights=split.map{word -> Double in
                    let letters=word.unicodeScalars.filter{CharacterSet.letters.contains($0)}.count
                    return min(2.1,max(0.65,sqrt(Double(max(1,letters)))/2))*(word.last.map{",;:.!?".contains($0)} == true ? 1.25:1)
                }
                let sum=max(1,weights.reduce(0,+));var cumulative=0.0
                var boundaries=[0.0]
                for weight in weights{cumulative+=weight/sum;boundaries.append(cumulative)}
                groups.append(Segment(start:start,end:end,range:lower..<words.count,boundaries:boundaries,exact:exact))
            }
        }
        tokens=words;segments=groups.sorted{$0.start<$1.start};hasEstimatedWords=estimated
        stars=ConstellationLayout.positions(count:words.count,seed:seed)
    }
    public func frame(at time:Double,duration:Double)->WordPlaybackFrame{
        guard time.isFinite,let segment=segments.last(where:{$0.start<=time}),!segment.range.isEmpty else{return .init(index:nil,entrance:0,exact:false)}
        let end=segment.end ?? (duration>segment.start ? duration:nil)
        if let end,time>=end{return .init(index:nil,entrance:0,exact:segment.exact)}
        if segment.exact{
            let transition=max(0.06,min(0.42,((end ?? segment.start+0.65)-segment.start)*0.65))
            return .init(index:segment.range.lowerBound,entrance:min(1,max(0,(time-segment.start)/transition)),exact:true)
        }
        guard let end,end>segment.start else{return .init(index:nil,entrance:0,exact:false)}
        let phase=min(0.999999,max(0,(time-segment.start)/(end-segment.start)))
        let local=min(segment.range.count-1,max(0,(segment.boundaries.lastIndex(where:{$0<=phase}) ?? 0)))
        let fraction=max(0.000001,segment.boundaries[local+1]-segment.boundaries[local])
        let entrance=min(1,(phase-segment.boundaries[local])/fraction*2.2)
        return .init(index:segment.range.lowerBound+local,entrance:entrance,exact:false)
    }
}

public enum SpotifyAudioPolicy{
    public static func includes(bundleID:String)->Bool{bundleID=="com.spotify.client" || bundleID.hasPrefix("com.spotify.client.")}
    public static func shouldRender(playing:Bool,connected:Bool,spotifySource:Bool,capturing:Bool,level:Double)->Bool{
        playing && connected && spotifySource && capturing && level>0.001
    }
}
