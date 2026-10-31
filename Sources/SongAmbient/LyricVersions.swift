import SwiftUI

struct LyricVersions:View{
    @ObservedObject var model:AppModel
    @ObservedObject var music:MusicWatcher
    @ObservedObject var lyrics:LyricsService
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var artist=""
    var body:some View{
        VStack(alignment:.leading,spacing:16){
            HStack{Text("Choose a lyric recording").font(.title3.bold());Spacer();Button("Done"){dismiss()}}
            Text("\(music.title) · \(music.artist) · \(PlayerCard.timestamp(music.catalogDuration))").font(.system(size:12)).foregroundStyle(.secondary)
            HStack{TextField("Song title",text:$title);TextField("Artist",text:$artist);Button("Search"){lyrics.findVersions(music:music,titleOverride:title,artistOverride:artist)}.disabled(title.trimmingCharacters(in:.whitespaces).isEmpty || artist.trimmingCharacters(in:.whitespaces).isEmpty)}.textFieldStyle(.roundedBorder)
            Text(lyrics.versionStatus).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if lyrics.findingVersions{ProgressView().frame(maxWidth:.infinity)}
            ScrollView{
                LazyVStack(spacing:9){ForEach(lyrics.versions){record in
                    Button{lyrics.choose(record,music:music);model.lyricsDemo=false;dismiss()}label:{
                        HStack(spacing:12){
                            VStack(alignment:.leading,spacing:5){Text(record.albumName?.isEmpty==false ? record.albumName!:"Unspecified album").font(.system(size:12,weight:.medium));Text("\(record.hasWordSync==true ? "Word sync":"Line sync") · record \(record.id)").font(.system(size:10)).foregroundStyle(.secondary)}
                            Spacer();VStack(alignment:.trailing,spacing:5){Text(record.duration.map{PlayerCard.timestamp($0)} ?? "Unknown length").font(.system(size:12,design:.monospaced));if let duration=record.duration{Text(abs(duration-music.catalogDuration)<=2 ? "Matching length":String(format:"%+.0f sec",duration-music.catalogDuration)).font(.system(size:10)).foregroundStyle(abs(duration-music.catalogDuration)<=2 ? .mint:.orange)}}
                        }.padding(13).frame(maxWidth:.infinity).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }}
            }.frame(maxHeight:.infinity)
        }.padding(22).frame(width:550,height:480).preferredColorScheme(.dark).task{title=music.title;artist=music.artist;lyrics.findVersions(music:music)}
    }
}
