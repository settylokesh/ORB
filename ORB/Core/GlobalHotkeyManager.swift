//
//  GlobalHotkeyManager.swift
//  ORB
//
//  System-wide hotkey via Carbon RegisterEventHotKey. Default ⌘Space
//  (note: this can conflict with Spotlight — onboarding warns the user).
//

import Foundation
import Carbon.HIToolbox

@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(cmdKey)) {
        unregister()

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                GlobalHotkeyManager.shared.onTrigger?()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4F524221), id: 1) // 'ORB!'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let h = hotKeyRef { UnregisterEventHotKey(h); hotKeyRef = nil }
        if let e = handlerRef { RemoveEventHandler(e); handlerRef = nil }
    }
}
