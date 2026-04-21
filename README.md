# EloquentHotkey

This is a menu bar macOS approximation of [Google AI Edge Eloquent](https://ai.google.dev/edge/eloquent): run it once, leave it in the toolbar, press a global hotkey, speak naturally, and your cleaned-up text gets copied to the clipboard and pasted into the current app.

It recreates the public workflow Google describes on its landing page. It does not reuse Google's private code, models, or assets.

## What it does

- Runs as a menu bar app with no Dock icon.
- Lets you choose a specific microphone instead of relying on the system default.
- Lets you change the global hotkey that starts and stops dictation.
- Uses Apple's speech framework, preferring on-device recognition when available.
- Cleans filler words like `um` and `uh`, fixes spacing, and normalizes capitalization.
- Keeps the last result on the clipboard.
- Auto-pastes into the previously focused app when Accessibility access is enabled.
- Lets you manually copy or paste the last result again from the menu bar or Settings window.

## Build

```bash
./scripts/build-app.sh
```

That creates:

`/Users/joe/Documents/Codex/2026-04-21-can-you-reverse-engineer-this-app/dist/EloquentHotkey.app`

## First run

Open the app once:

```bash
open /Users/joe/Documents/Codex/2026-04-21-can-you-reverse-engineer-this-app/dist/EloquentHotkey.app
```

macOS should prompt for:

- Microphone access
- Speech Recognition access
- Accessibility access, if you want auto-paste

After it launches, you'll see a waveform icon in the menu bar.

If Accessibility is not granted, the app still copies the dictated text to the clipboard and keeps the last result available in the menu.

## Configure it

Open the menu bar app and choose `Settings…`.

From Settings you can change:

- The default microphone
- The global hotkey
- Whether auto-paste is enabled
- Whether cleanup is enabled
- The silence timeout
- The maximum recording length

The default hotkey is `Control + Option + Space`.

## Daily use

1. Launch the app once so it lives in the menu bar.
2. Press the configured global hotkey.
3. Speak.
4. Pause for about a second, or press the hotkey again to stop manually.

The app copies the last result to the clipboard every time. If the original text field misses focus and auto-paste does not land, use either:

- `Paste Last Result` from the menu bar
- `Copy Last Result` from the menu bar, then paste manually yourself

## Development

You can still run the binary directly during development:

```bash
$(swift build -c release --show-bin-path)/EloquentHotkey
```
