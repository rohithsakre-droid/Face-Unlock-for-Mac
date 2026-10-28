import Foundation
import ApplicationServices

class UnlockService {
    static func typePasswordAndUnlock(password: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        Thread.sleep(forTimeInterval: 0.3)
        
        for char in password.utf16 {
            var unicodeChar = char
            
            if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                eventDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
                eventDown.post(tap: .cghidEventTap)
            }
            
            if let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                eventUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
                eventUp.post(tap: .cghidEventTap)
            }
            
            Thread.sleep(forTimeInterval: 0.02)
        }
        
        // Return key (0x24 / Virtual Key 36)
        if let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
           let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) {
            returnDown.post(tap: .cghidEventTap)
            returnUp.post(tap: .cghidEventTap)
        }
    }
}
