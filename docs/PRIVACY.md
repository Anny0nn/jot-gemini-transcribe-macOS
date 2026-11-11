# Privacy

## The promise

Your voice goes from your Mac directly to Google's Gemini API, using your own API
key. There is no middleman server, no account, no analytics, no telemetry.
Everything else stays on your Mac. The code is open — verify all of this.

## What leaves your machine (the complete list)

1. **The audio of each dictation** (FLAC-compressed), sent to
   `generativelanguage.googleapis.com` — the only network host this app talks to.
2. **Your dictionary terms**, alongside that audio. The transcription model uses
   them to bias what it hears, which is why names and jargon come out spelled
   right as you speak rather than being corrected afterwards. Only the correct
   spellings are sent — never the misspellings you record. They ride on every
   dictation, including with Smart transcription off.
3. **The formatting prompt** — a second, text-only request — when "Polish into
   finished writing" (on by default) or "Match tone to the app you're in" (off
   by default) is on in Settings → Dictation. It contains the transcript being
   rewritten, the rewriting rules, your dictionary terms, and — only with tone
   matching on — a coarse tone category derived from the frontmost app's
   *category* (e.g. "chat message"). The audio is not sent a second time. With
   both settings off, your transcript text never leaves this Mac at all.
   Never window contents, never screenshots, never surrounding text.
4. **Your API key**, in the request header to Google only. It is stored in the
   macOS Keychain, never in files or preferences.

## What never leaves

- Your history database and stored recordings — audio and transcript text leave
  only as part of the requests above, never in bulk and never anywhere else
- Your dictionary as a file. Individual terms ride with the audio as described
  above, and your misspelling rules are included in the formatting prompt *only*
  when polish or tone matching is on — with both off they never leave. The
  store itself, and everything you have not dictated against, stays on this Mac
- Which apps you use, when you dictate, or anything you type
- Keystrokes: the event tap watches your dictation key, plus — only while a
  dictation is active — Esc (cancel), Space (the hands-free gesture), and the
  *fact that* another key was pressed (the accidental-chord guard; which key it
  was is never examined beyond its keycode, never logged, never stored, never
  transmitted). When you're not dictating, other keys pass through untouched.
- Screenshots, screen contents, system audio: never captured. The app contains
  no screen-capture code and records only the microphone.
- Accessibility: used only to type into the field you are dictating into. Jot
  reads that one field's role (to refuse password fields) and its value before
  and after inserting (to confirm the text landed and never double-insert). It
  does not read other UI, other apps or other windows, and nothing it reads
  leaves the Mac or is stored. The pill finds your screen from window bounds,
  never window titles or contents.
- Telemetry: there is none. No analytics SDK, no crash uploader, no phone-home.

## What's stored locally, and your controls

- **By default nothing is kept.** "Keep dictation history" (Settings → Privacy &
  Storage) is off: a dictation's recording and transcript are deleted the moment
  the text reaches your cursor or clipboard, and Esc deletes a dictation of any
  length. While you speak, audio is written to a folder
  (`~/Library/Application Support/Jot/recordings/`) so a crash or a dropped
  connection can't lose it; that folder does not outlive the dictation.
- The exception is words that have not been delivered yet — offline, failed, or
  held because a password field had focus. Those stay in History so they can be
  retried, until you retry or delete them.
- With history on: one folder per dictation (crash-safe audio, transcript,
  metadata) powers History, Retry and recovery; audio retention (24h / 7d / 30d /
  forever / never — "never" disables Retry) applies; and **Delete all history**
  is one click.
- Turning history off does not delete what is already in History — use Delete
  all history for that.
- Local files are protected by FileVault if enabled; they are not separately
  encrypted (stated honestly).

## Google's side of the wire

Your audio is governed by your own Gemini API terms with Google. As of writing,
paid-tier API usage is not used for model training; free-tier usage may be. That
relationship is yours — this app doesn't broker it. Review the
[Gemini API terms](https://ai.google.dev/gemini-api/terms).

## Secure input

When a password field is focused (secure input), dictation refuses to start, and
a transcript in flight is held in History only — never inserted, never placed on
the clipboard.

## Verify it

- Build from source (`./scripts/build.sh`).
- Watch traffic with Little Snitch or `nettop` — you'll see exactly one host.
- Read the prompts: they're source files —
  [PolishPrompt.swift](../JotCore/Sources/FormattingPipeline/PolishPrompt.swift)
  (the polish rewrite) and
  [PromptV1.swift](../JotCore/Sources/FormattingPipeline/PromptV1.swift) (tone
  matching alone). With both off, formatting happens inside Google's
  transcription model and there is no local prompt to read.
