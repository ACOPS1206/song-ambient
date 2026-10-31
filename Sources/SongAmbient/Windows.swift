import AppKit
import SwiftUI
import IOKit.pwr_mgt
import OSLog

enum AppWindowRole: String { case studio, stage }

@MainActor final class WindowCoordinator {
    static let shared = WindowCoordinator()
    private final class Entry { weak var window: NSWindow?;init(_ window:NSWindow){self.window=window} }
    private var windows:[AppWindowRole:Entry]=[:]
    private var observers:[NSObjectProtocol]=[]
    private var stageDisplay="automatic"
    private var fullScreenRequested=false
    private var pendingMove=false
    var onStageVisibility:((Bool)->Void)?
    private let stageAwake=AwakeController()
    private var keepStageAwake=false
    private let logger=Logger(subsystem:"local.rachit.songambient",category:"windows")

    func attach(_ window:NSWindow,role:AppWindowRole) {
        guard windows[role]?.window !== window else{return}
        windows[role]=Entry(window)
        window.isReleasedWhenClosed=false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize=NSSize(width:760,height:500)
        if role == .studio {
            window.setFrameAutosaveName("SongAmbient.Studio.v2")
            if !UserDefaults.standard.bool(forKey:"layout.v2") {
                let visible=window.screen?.visibleFrame ?? NSScreen.screens.first!.visibleFrame
                window.setContentSize(NSSize(width:min(940,visible.width-80),height:min(620,visible.height-80)))
                window.center();UserDefaults.standard.set(true,forKey:"layout.v2")
            }
            if let visible=window.screen?.visibleFrame,window.frame.height>visible.height {
                window.setFrame(NSRect(x:visible.minX+40,y:visible.minY+40,width:min(940,visible.width-80),height:visible.height-80),display:true)
            }
        } else {
            window.title="Song Ambient · Lyrics"
            window.backgroundColor = .black;window.isOpaque=true
            window.titlebarAppearsTransparent=true
            if fullScreenRequested { showStageWindow(window) }
        }
        let center=NotificationCenter.default
        observers.append(center.addObserver(forName:NSWindow.willCloseNotification,object:window,queue:.main){[weak self] _ in
            Task { @MainActor in
                guard let self else{return}
                self.logger.info("Window closed: \(role.rawValue,privacy:.public)")
                if role == .stage {self.onStageVisibility?(false);self.stageAwake.setEnabled(false)}
                DispatchQueue.main.async { self.updateDock() }
            }
        })
        observers.append(center.addObserver(forName:NSWindow.didBecomeKeyNotification,object:window,queue:.main){_ in if NSApp.activationPolicy() != .regular {NSApp.setActivationPolicy(.regular)}})
        if role == .stage {
            observers.append(center.addObserver(forName:NSWindow.didEnterFullScreenNotification,object:window,queue:.main){[weak self]_ in self?.logger.info("Lyrics entered native full screen")})
            observers.append(center.addObserver(forName:NSWindow.didExitFullScreenNotification,object:window,queue:.main){[weak self,weak window] _ in
                Task { @MainActor in
                    guard let self,let window,self.pendingMove else{return}
                    self.pendingMove=false;self.positionStage(window);window.toggleFullScreen(nil)
                }
            })
        }
    }
    func revealStudio() {
        if NSApp.activationPolicy() != .regular {NSApp.setActivationPolicy(.regular)}
        if let window=windows[.studio]?.window { window.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps:true)
        logger.info("Studio requested; Dock policy regular")
    }
    @discardableResult func prepareStage(display:String)->Bool {
        stageDisplay=display;fullScreenRequested=true
        if NSApp.activationPolicy() != .regular {NSApp.setActivationPolicy(.regular)}
        if let window=windows[.stage]?.window { showStageWindow(window);return false }
        return true
    }
    func moveStage(to display:String) {
        stageDisplay=display
        guard let window=windows[.stage]?.window else{return}
        if window.styleMask.contains(.fullScreen) {pendingMove=true;window.toggleFullScreen(nil)}else{positionStage(window)}
    }
    func exitFullScreen() {
        fullScreenRequested=false
        if let window=windows[.stage]?.window,window.styleMask.contains(.fullScreen){window.toggleFullScreen(nil)}
    }
    func closeStage() {
        fullScreenRequested=false
        windows[.stage]?.window?.close()
        revealStudio()
    }
    func setKeepStageAwake(_ value:Bool){
        keepStageAwake=value
        stageAwake.setEnabled(value && windows[.stage]?.window?.isVisible==true)
    }
    private func positionStage(_ window:NSWindow) {
        let screen=NSScreen.screens.first{$0.ambientID==stageDisplay} ?? window.screen ?? NSScreen.screens.first
        if let frame=screen?.visibleFrame {window.setFrame(frame,display:true)}
    }
    private func showStageWindow(_ window:NSWindow) {
        NSApp.activate(ignoringOtherApps:true)
        window.makeKeyAndOrderFront(nil)
        onStageVisibility?(true);stageAwake.setEnabled(keepStageAwake)
        guard !window.styleMask.contains(.fullScreen) else{return}
        positionStage(window)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.25){[weak self,weak window] in
            guard let self,let window,self.fullScreenRequested,window.isVisible,!window.styleMask.contains(.fullScreen) else{return}
            window.styleMask.insert(.resizable)
            window.collectionBehavior.subtract([.fullScreenAuxiliary,.fullScreenNone])
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.makeKeyAndOrderFront(nil);window.toggleFullScreen(nil)
        }
    }
    private func updateDock() {
        let visible=windows.values.contains{$0.window?.isVisible==true}
        if !visible { NSApp.setActivationPolicy(.accessory);logger.info("No studio or stage visible; Dock policy accessory; menu bar retained") }
    }
}

struct WindowAttachment:NSViewRepresentable {
    let role:AppWindowRole
    final class AttachmentView:NSView {
        var role=AppWindowRole.studio
        override func viewDidMoveToWindow(){super.viewDidMoveToWindow();if let window{DispatchQueue.main.async{WindowCoordinator.shared.attach(window,role:self.role)}}}
    }
    func makeNSView(context:Context)->AttachmentView{let view=AttachmentView();view.role=role;return view}
    func updateNSView(_ nsView:AttachmentView,context:Context){}
}

@MainActor final class AwakeController {
    private var assertion:IOPMAssertionID=0
    func setEnabled(_ enabled:Bool){
        if enabled && assertion==0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,IOPMAssertionLevel(kIOPMAssertionLevelOn),"Song Ambient immersive lyrics" as CFString,&assertion)
        }else if !enabled && assertion != 0 { IOPMAssertionRelease(assertion);assertion=0 }
    }
    deinit { if assertion != 0 { IOPMAssertionRelease(assertion) } }
}

enum Branding {
    static let menuIcon:NSImage={
        let image=NSImage(size:NSSize(width:19,height:19),flipped:true){rect in
            NSColor.labelColor.setStroke();NSColor.labelColor.setFill()
            let p=NSBezierPath();p.lineWidth=1.8;p.lineCapStyle = .round
            p.move(to:NSPoint(x:15.5,y:3.7));p.curve(to:NSPoint(x:8,y:9.5),controlPoint1:NSPoint(x:1,y:0),controlPoint2:NSPoint(x:0,y:7.5))
            p.curve(to:NSPoint(x:4.3,y:16.2),controlPoint1:NSPoint(x:21,y:12),controlPoint2:NSPoint(x:16,y:20));p.stroke()
            NSBezierPath(ovalIn:NSRect(x:14,y:2.2,width:3,height:3)).fill();return true
        };image.isTemplate=true;return image
    }()
}
