// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import ApplicationServices
import Foundation

/// Tier 1: direct Accessibility insertion at the cursor — no clipboard involved.
///
/// Verification is mandatory: Electron apps report AX set success without
/// inserting (Electron #36337/#37465). We verify by comparing the element's value
/// before and after — substitution-proof (smart quotes) and lie-proof: if the
/// value didn't change, the insert didn't happen and the ladder falls through.
@MainActor
public enum AXInserter {
    public enum Result {
        case landed
        /// AX couldn't do it here — the paste tier is still appropriate.
        case notPossible
        /// PROVEN focus theft: the focused element belongs to a different app.
        /// A blind ⌘V would paste the transcript into the thief.
        case focusElsewhere
    }

    public static func insert(_ text: String, targetPID: pid_t?, bundleID: String?) async -> Result {
        if let bundleID, AppQuirks.forcePaste.contains(bundleID) {
            return .notPossible
        }
        // The Chromium a11y wake now happens at session START (AccessibilityWaker),
        // so it never blocks the user's wait for their words.
        let system = AXUIElementCreateSystemWide()
        // A hung target would park this @MainActor call until the system default
        // messaging timeout (seconds), stalling the pill, the status item and the
        // hotkey intent stream behind it. Bound it — a target that can't answer
        // in 1.5s is demoted to the paste tier instead of freezing the app.
        // Deliberately generous: a premature timeout on the SET below would fall
        // through to ⌘V and DOUBLE-INSERT (audit #9).
        AXUIElementSetMessagingTimeout(system, 1.5)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return .notPossible
        }
        let element = unsafeDowncast(focused as AnyObject, to: AXUIElement.self)

        // The system-wide focused element must belong to the app the user was
        // dictating into — not whatever stole focus a frame ago (audit L24).
        if let targetPID {
            var elementPID: pid_t = 0
            if AXUIElementGetPid(element, &elementPID) == .success, elementPID != targetPID {
                // Name BOTH sides. "A different app" alone made a false positive
                // that fired on every dictation in one terminal undiagnosable:
                // the only way to tell real focus theft (Spotlight, a launcher)
                // from a helper process of the target app is to see who it is.
                // Process identity only — never the element's contents.
                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
                Log.insertion.info("AXInserter: focused element belongs to a different process — chip, never blind paste. target=\(Self.describe(targetPID), privacy: .public) focused=\(Self.describe(elementPID), privacy: .public) role=\((roleRef as? String) ?? "?", privacy: .public)")
                return .focusElsewhere
            }
        }

        // Never write into secure fields.
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String, role == "AXSecureTextField" {
            return .notPossible
        }

        // Readable value is the precondition for verification; without it we cannot
        // prove the insert landed, so we fall to paste rather than risk a double.
        guard let before = stringValue(of: element) else { return .notPossible }

        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        guard settable.boolValue else { return .notPossible }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success else {
            return .notPossible
        }

        var after = stringValue(of: element)
        var landed = after != nil && after != before
        if !landed {
            // Some apps (web content, async editors) update the AX value a beat
            // late; re-check before falling to paste — a false negative here
            // would DOUBLE-insert (AX landed + ⌘V lands again; audit #9). Poll
            // rather than sleep the full budget: most apps answer on the first
            // step, and only the slow ones pay the rest.
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 40_000_000)
                after = stringValue(of: element)
                landed = after != nil && after != before
                if landed { break }
            }
        }
        if !landed {
            Log.insertion.info("AXInserter: set reported success but value unchanged after re-check — falling to paste")
        }
        return landed ? .landed : .notPossible
    }

    /// The process that owns the system-wide focused UI element — where typing
    /// would go right now. Nil when Accessibility can't say (no trust, nothing
    /// focused, an unresponsive app).
    static func focusedProcessID() -> pid_t? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.5)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(unsafeDowncast(focused as AnyObject, to: AXUIElement.self), &pid) == .success else {
            return nil
        }
        return pid
    }

    /// "pid bundleID (executable path)" for a process — enough to tell a helper
    /// of the target app from another app entirely.
    static func describe(_ pid: pid_t) -> String {
        let app = NSRunningApplication(processIdentifier: pid)
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let path = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0
            ? String(cString: pathBuffer) : (app?.executableURL?.path ?? "?")
        return "\(pid) \(app?.bundleIdentifier ?? "no-bundle-id") (\(path))"
    }

    private static func stringValue(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
    }

    /// Chromium builds its a11y tree lazily; AXManualAccessibility asks for it
    /// without the VoiceOver-reserved side effects. First set can take a moment on
    /// big apps — the ladder's fallback covers the not-ready case.
}
