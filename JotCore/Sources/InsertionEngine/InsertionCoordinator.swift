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
import Foundation

/// The 3-tier ladder with the two guards that fix Wispr's most-reported bugs:
///
///   guard 1: frontmost app changed since dictation started → NEVER paste blind
///            (text goes to the clipboard; the HUD offers it — F17)
///   guard 2: secure input active → refuse entirely, no clipboard leak (F18)
///
///   tier 1: AX kAXSelectedTextAttribute with read-back verification
///   tier 2: pasteboard + synthesized ⌘V with guarded restore
///   tier 3: text left on the clipboard, visible hint
public struct InsertionCoordinator: TextInserting {
    private let paster: PasteInserter

    @MainActor
    public init() {
        self.paster = PasteInserter()
    }

    @MainActor
    public func insert(_ text: String, context: DictationContext) async -> InsertionOutcome {
        // Guard 2: secure input — the transcript stays in History only.
        if SecureInput.isActive {
            Log.insertion.warning("secure input active at insert time — refusing (text in History only)")
            return .blockedSecureField
        }

        if SettingsStore().pasteIntoCurrentFocus {
            return await insertAtCurrentFocus(text)
        }

        // Guard 1: is the user still where they started dictating?
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let expectedPID = context.targetPID, let frontmost, frontmost.processIdentifier != expectedPID {
            Log.insertion.info("frontmost changed (\(context.targetAppName ?? "?", privacy: .private) → \(frontmost.localizedName ?? "?", privacy: .private)) — no blind paste")
            paster.copyOnly(text)
            return .frontmostChanged
        }

        // Tier 1: AX direct insertion.
        switch await AXInserter.insert(text, targetPID: context.targetPID, bundleID: context.targetAppBundleID) {
        case .landed:
            Log.insertion.info("inserted via AX")
            return .inserted
        case .focusElsewhere:
            // PROVEN focus theft — a blind ⌘V would paste into the thief.
            // Same treatment as the frontmost-changed guard: chip, never blind.
            paster.copyOnly(text)
            return .frontmostChanged
        case .notPossible:
            break
        }

        // Guard 1 re-check: the AX attempt takes up to ~350ms — a ⌘Tab in that
        // window would land the ⌘V in the wrong app (production pass 2).
        if let expectedPID = context.targetPID,
           let nowFront = NSWorkspace.shared.frontmostApplication,
           nowFront.processIdentifier != expectedPID {
            Log.insertion.info("frontmost changed during AX attempt — no blind paste")
            paster.copyOnly(text)
            return .frontmostChanged
        }

        // Tier 2: guarded paste. Note: "true" means the ⌘V was POSTED — there is
        // no OS-level delivery receipt for synthetic paste (industry-wide floor;
        // the text also stays recoverable in History).
        if await paster.paste(text) {
            Log.insertion.info("⌘V posted (delivery is best-effort)")
            return .inserted
        }

        // Tier 3: clipboard floor.
        paster.copyOnly(text)
        return .fellBackToClipboard
    }

    /// "Paste wherever I am": the same ladder with the where-did-you-start guards
    /// removed. The target is whatever holds keyboard focus NOW — judged by the
    /// focused element's owner, not by the "frontmost" app, which is wrong for
    /// floating windows (iTerm's hotkey window types into iTerm while macOS still
    /// reports the app underneath as frontmost).
    @MainActor
    private func insertAtCurrentFocus(_ text: String) async -> InsertionOutcome {
        let focusedPID = AXInserter.focusedProcessID()
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Per-app quirks (terminals → straight to paste) follow the focused app.
        let bundleID = focusedPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        if case .landed = await AXInserter.insert(text, targetPID: nil, bundleID: bundleID) {
            Log.insertion.info("inserted via AX at current focus")
            return .inserted
        }
        // ⌘V goes to whatever has keyboard focus — which is the point here.
        if await paster.paste(text) {
            Log.insertion.info("⌘V posted at current focus (\(bundleID ?? "unknown app", privacy: .public))")
            return .inserted
        }
        paster.copyOnly(text)
        return .fellBackToClipboard
    }
}
