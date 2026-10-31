import SwiftUI

enum RimStyle: String, CaseIterable, Codable, Identifiable {
    case aurora = "Aurora", comet = "Comet", waves = "Waves", spectrum = "Spectrum", ribbons = "Ribbons", minimal = "Minimal"
    var id:String{rawValue}
    var shaderID:Int{switch self{case .aurora:return 1;case .comet:return 2;case .waves:return 3;case .spectrum:return 4;case .ribbons:return 8;case .minimal:return 9}}
    var symbol:String{switch self{case .aurora:return "sparkles";case .comet:return "moon.stars";case .waves:return "water.waves";case .spectrum:return "waveform";case .ribbons:return "wind";case .minimal:return "rectangle"}}
    init(from decoder:Decoder)throws{let value=try decoder.singleValueContainer().decode(String.self);self=Self(rawValue:value) ?? .aurora}
    func encode(to encoder:Encoder)throws{var container=encoder.singleValueContainer();try container.encode(rawValue)}
}
enum LyricStyle: String, CaseIterable, Codable, Identifiable {
    case ship = "Ship", fisheye = "Fisheye", visual = "Visual", fisheyeVisual = "Fisheye Visual", code = "Codestyle", codeVisual = "Codestyle Visual", branches = "Branches", web = "Web", constellation = "Constellation"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .ship: return "paperplane"; case .fisheye: return "circle.inset.filled"; case .visual: return "sparkles.tv"; case .fisheyeVisual: return "eye"; case .code: return "chevron.left.forwardslash.chevron.right"; case .codeVisual: return "terminal"; case .branches: return "point.3.connected.trianglepath.dotted"; case .web: return "network"; case .constellation: return "sparkles" }
    }
    var showsArtwork: Bool { self == .visual || self == .fisheyeVisual || self == .codeVisual }
}
enum LyricFont: String, CaseIterable, Codable, Identifiable {
    case sfPro = "SF Pro", rounded = "SF Rounded", newYork = "New York", helvetica = "Helvetica Neue", avenir = "Avenir Next", futura = "Futura", didot = "Didot"
    var id: String { rawValue }
    func font(size: Double, weight: Font.Weight = .medium) -> Font {
        switch self {
        case .sfPro: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .newYork: return .system(size: size, weight: weight, design: .serif)
        case .helvetica: return .custom("HelveticaNeue", size: size)
        case .avenir: return .custom("AvenirNext-Medium", size: size)
        case .futura: return .custom("Futura-Medium", size: size)
        case .didot: return .custom("Didot", size: size)
        }
    }
}
enum StudioTab: String, CaseIterable { case lighting = "Lighting", lyrics = "Lyrics Studio", settings = "Settings" }

struct OrbitMark: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w*0.8,y: h*0.2))
                    p.addCurve(to: CGPoint(x: w*0.42,y: h*0.49), control1: CGPoint(x:w*0.05,y:h*0.03),control2:CGPoint(x:w*0.02,y:h*0.39))
                    p.addCurve(to: CGPoint(x: w*0.22,y: h*0.84), control1: CGPoint(x:w*1.08,y:h*0.63),control2:CGPoint(x:w*0.83,y:h*1.02))
                }.stroke(style: StrokeStyle(lineWidth: w*0.095,lineCap:.round))
                Circle().frame(width:w*0.17,height:w*0.17).position(x:w*0.8,y:h*0.2)
            }
        }.aspectRatio(1,contentMode:.fit)
    }
}
