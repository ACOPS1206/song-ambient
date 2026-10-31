import SwiftUI
import AppKit

struct WheelControl: View {
    let label: String
    @Binding var hex: String
    @Binding var brightness: Double
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) { Text(label).font(.system(size: 11, weight: .semibold)); Text("\(Int(brightness * 100))%").font(.system(size: 10)).foregroundStyle(.secondary) }
            ColorWheel(hex: $hex).frame(width:112,height:112).brightness(brightness - 1)
            HStack(spacing: 5) { Image(systemName: "sun.min").font(.system(size: 9)); Slider(value: $brightness, in: 0.05...1).controlSize(.mini); Image(systemName: "sun.max").font(.system(size: 9)) }.foregroundStyle(.secondary)
            TextField("Hex", text: $hex).font(.system(size: 10, design: .monospaced)).textFieldStyle(.plain).multilineTextAlignment(.center)
                .onSubmit { hex = Color(hex: hex).hex }
        }.frame(maxWidth: .infinity)
    }
}

struct ColorWheel: View {
    @Binding var hex: String
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height), radius = size / 2
            let color = NSColor(Color(hex: hex)).usingColorSpace(.sRGB) ?? .systemPink
            let angle = color.hueComponent * .pi * 2
            ZStack {
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle().stroke(.white, lineWidth: 2).background(Circle().fill(.black.opacity(0.12))).frame(width: 19, height: 19)
                    .position(x: radius + cos(angle) * color.saturationComponent * (radius - 9), y: radius + sin(angle) * color.saturationComponent * (radius - 9))
            }.frame(width: size, height: size)
                .contentShape(Circle()).gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    let dx = event.location.x - radius, dy = event.location.y - radius
                    let hue = (atan2(dy, dx) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
                    let saturation = min(1, hypot(dx, dy) / radius)
                    hex = Color(nsColor: NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1)).hex
                })
                .accessibilityLabel("\(hex) color wheel")
        }
    }
}
