# Hailer

*hailer — the loud-hailer, a ship's speaking trumpet for carrying the captain's words over the wind.*

Hailer is a native macOS teleprompter in the spirit of TalkProp. Write your script, set a pace you can actually read at, and raise a floating prompter that scrolls silkily above every other window — or collapse it into a one-line ticker that tucks under your camera. When you stop, Hailer remembers where you were, so the next take starts where the last one ended.

## Features

- Script library in a two-pane window: plain-text scripts saved as JSON under `~/Library/Application Support/Hailer/`, with word count and a read-time estimate.
- Prompter window (⌘P): always-on-top, resizable, with a true fullscreen option (F). Dark background, big type, adjustable font size, line spacing, and side margins.
- Smooth auto-scroll: a 60 fps tick with sub-pixel accumulation, so motion stays even at slow speeds. Speed slider from 10 to 400 pt/s.
- Keyboard transport: SPACE pauses/resumes, ←/↓ and →/↑ nudge speed, R restarts, T flips to ticker, M mirrors, F fullscreen, ESC closes.
- Scroll-wheel / trackpad scrubbing: grabbing the script pauses the auto-scroll and it resumes on its own a beat after you let go.
- Ticker mode (T): the prompter collapses into a thin always-on-top strip parked at the top of the screen, streaming the script on one line at the same speed, with the same pause and scrub controls.
- Eye-line marker arrows and an optional horizontal mirror flip for beam-splitter rigs.
- Thin progress bar plus elapsed/remaining estimates based on the current speed.
- Per-script resume: each script remembers its position; a "Reset position" button in the editor clears it.

## Build

```
./make-app.sh
```

Builds the release binary, generates the icon, assembles `Hailer.app`, installs it to `/Applications`, and launches it.

## Permissions

None. Hailer needs no Accessibility, Screen Recording, or network access — it is just windows, text, and a clock.

## Not yet

- Rich text or Markdown rendering (scripts are plain text)
- Voice-tracking / auto-pacing
- Remote control from another device
