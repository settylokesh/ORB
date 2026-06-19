//
//  KeyboardController.swift
//  ORB
//
//  Real keyboard typing and shortcuts via CGEvent.
//

import Foundation
import CoreGraphics
import Carbon.HIToolbox

enum KeyboardController {

    /// Type arbitrary text by posting unicode keystrokes (no keymap needed).
    static func type(_ text: String) {
        for scalar in text.unicodeScalars {
            postUnicode(UniChar(scalar.value > 0xFFFF ? 0x20 : scalar.value))
        }
    }

    private static func postUnicode(_ code: UniChar) {
        var c = code
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
        up?.post(tap: .cghidEventTap)
    }

    /// Press a key combo like "cmd+l", "cmd+shift+4", "return", "tab".
    static func pressCombo(_ combo: String) {
        let parts = combo.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        var flags: CGEventFlags = []
        var keyCode: CGKeyCode?
        for p in parts {
            switch p {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift":          flags.insert(.maskShift)
            case "alt", "option":  flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default:               keyCode = code(for: p)
            }
        }
        guard let key = keyCode else { return }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    private static func code(for key: String) -> CGKeyCode? {
        let map: [String: Int] = [
            "a": kVK_ANSI_A, "c": kVK_ANSI_C, "l": kVK_ANSI_L, "n": kVK_ANSI_N,
            "t": kVK_ANSI_T, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5,
            "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab,
            "space": kVK_Space, "escape": kVK_Escape, "esc": kVK_Escape,
            "delete": kVK_Delete, "left": kVK_LeftArrow, "right": kVK_RightArrow,
            "up": kVK_UpArrow, "down": kVK_DownArrow,
        ]
        if let v = map[key] { return CGKeyCode(v) }
        return nil
    }
}
