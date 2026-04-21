# EloquentHotkey

`EloquentHotkey` is a fast macOS menu bar dictation app built for one job: hold a shortcut, talk, release, and get cleaned-up text back in the app you were already using.

It is inspired by the workflow of Google AI Edge Eloquent, but it is an independent macOS app built with Apple's speech stack, Apple-friendly on-device cleanup when available, and a lightweight local fallback when it is not.

## Why it exists

The best voice-to-text tools disappear into your workflow. `EloquentHotkey` stays in the menu bar, listens while you hold a global shortcut, cleans up the transcript, and pastes it back where you were typing.

That means:

- no big window to manage
- no mode switching
- no copying text around by hand
- no waiting on a cloud round-trip just to remove `um` and fix `GitHub`

## What it does

- Runs as a menu bar app with no Dock icon.
- Supports global hold-to-talk dictation.
- Lets you use `Fn` by itself as the shortcut, or pick another shortcut.
- Uses Apple's Speech framework for transcription, preferring on-device recognition when the system supports it.
- Cleans up transcripts before paste.
- Uses Apple's on-device Foundation Models cleanup path when available on the current Mac.
- Falls back to a very fast local cleanup pass when Apple Intelligence is unavailable.
- Preserves technical terms like `GitHub`, `macOS`, `SwiftUI`, `OpenAI`, `JSON`, and `API`.
- Lets you choose a microphone instead of always using the system default.
- Auto-pastes back into the previously focused app when Accessibility access is enabled.
- Keeps the last transcript available from both the menu bar and Settings.
- Shows visual menu bar state for listening and cleanup.

## How it feels

1. Launch the app once so it lives in the menu bar.
2. Hold your shortcut.
3. Speak naturally.
4. Release the shortcut.
5. The app cleans the transcript and pastes it back where you were working.

If auto-paste misses, the cleaned result is still on the clipboard and available through `Paste Last Result` or `Copy Last Result`.

## Cleanup behavior

`EloquentHotkey` has two cleanup modes:

- Apple on-device cleanup:
  Uses Apple's Foundation Models APIs for a more context-aware cleanup pass when Apple Intelligence is available on the machine and enabled for the current OS session.
- Fast local cleanup:
  Uses a lightweight regex-based cleanup pass that is intentionally fast and tuned for dictation output, filler words, spacing, capitalization, and developer/product names.

The Settings window shows which cleanup engine is active on the current Mac.

## Permissions

Depending on how you use the app, macOS may ask for:

- `Microphone`
- `Speech Recognition`
- `Accessibility`
- `Input Monitoring`

These matter for different reasons:

- `Microphone` and `Speech Recognition` are required for dictation.
- `Accessibility` is required for auto-paste.
- `Input Monitoring` is required for reliable global hotkey capture, especially for keys like `Fn`.

If a permission is missing, the app falls back as gracefully as it can and keeps the last result accessible.

## Settings

From `Settings…` you can change:

- microphone
- global shortcut
- auto-paste
- transcript cleanup
- silence timeout for manual menu-started dictation
- maximum recording length
- live cleanup engine status for the current machine

The default shortcut is `Control + Option + Space`, but `Fn`-only shortcuts are supported too.

## Build

Build the app bundle with:

```bash
./scripts/build-app.sh
```

That produces:

```text
/Volumes/External/local-code-e/eloquent-hotkey-mac/dist/EloquentHotkey.app
```

The build script copies bundled resources, generates the app icon, and signs the app. If a stable local signing identity is available, it uses that automatically so macOS permissions survive rebuilds much more reliably.

## Development

Run tests with:

```bash
swift test
```

If you want to run the built binary directly during development:

```bash
$(swift build -c release --show-bin-path)/EloquentHotkey
```

## Notes

- This project recreates the product experience, not Google's private implementation.
- It does not use Google's code, models, or assets.
- It is designed to feel fast first, with better cleanup layered in when the local system can support it.
