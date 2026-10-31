import AppKit
import SwiftUI
import Combine

@MainActor final class DesktopLyricsController{
    private let model:AppModel
    private var panel:NSPanel?
    private var tokens=Set<AnyCancellable>()
    private var observers:[NSObjectProtocol]=[]
    private var locked=false
    init(model:AppModel){
        self.model=model
        model.$prefs.map(\.desktopLyrics).removeDuplicates().sink{[weak self]_ in DispatchQueue.main.async{self?.update()}}.store(in:&tokens)
        model.$stageVisible.removeDuplicates().sink{[weak self]_ in DispatchQueue.main.async{self?.update()}}.store(in:&tokens)
        model.$prefs.map(\.stageDisplay).removeDuplicates().sink{[weak self]_ in DispatchQueue.main.async{self?.update()}}.store(in:&tokens)
        model.lyrics.$presentation.map{$0.tokens.isEmpty}.removeDuplicates().sink{[weak self]_ in DispatchQueue.main.async{self?.update()}}.store(in:&tokens)
        let center=DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName:.init("com.apple.screenIsLocked"),object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.locked=true;self?.update()}})
        observers.append(center.addObserver(forName:.init("com.apple.screenIsUnlocked"),object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.locked=false;self?.update()}})
    }
    private func update(){
        guard model.prefs.desktopLyrics,!model.stageVisible,!locked,!model.lyrics.presentation.tokens.isEmpty else{panel?.orderOut(nil);return}
        guard let screen=NSScreen.screens.first(where:{$0.ambientID==model.prefs.stageDisplay}) ?? NSScreen.main else{return}
        if panel==nil{
            let panel=PassivePanel(contentRect:screen.visibleFrame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false;panel.ignoresMouseEvents=true;panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false
            panel.level = .floating;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
            let hosting=NSHostingView(rootView:LyricCanvas(model:model,music:model.music,audio:model.audio,lyrics:model.lyrics,transparent:true))
            hosting.wantsLayer=true;hosting.layer?.backgroundColor=NSColor.clear.cgColor;panel.contentView=hosting;self.panel=panel
        }
        panel?.setFrame(screen.visibleFrame,display:true);panel?.orderFrontRegardless()
    }
}
