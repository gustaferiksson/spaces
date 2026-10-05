# spaces

Instant Ctrl+←/→ switching between macOS Spaces, without the slide animation.
Ctrl+Option+Cmd+C opens Control Center (press it again to close).

```sh
brew install gustaferiksson/tap/spaces
brew services start spaces
```

Then:

1. Grant Accessibility access to `spaces` when prompted (System Settings →
   Privacy & Security → Accessibility). The daemon waits until it has it.
2. Untick **Move left a space** and **Move right a space** in System Settings →
   Keyboard → Keyboard Shortcuts → Mission Control, so macOS doesn't take
   Ctrl+←/→ first.

Releases are signed with a Developer ID and notarized, so the Accessibility
grant survives `brew upgrade`.

## Commands

```sh
spaces daemon   # listen for Ctrl+←/→ and Ctrl+Option+Cmd+C (what brew services runs)
spaces left     # switch one Space left and exit
spaces right    # switch one Space right and exit
```

Switching stops at the first and last Space instead of bouncing. With several
displays it follows the display under the pointer.

Without the slide it's easy to lose track, so every Space change (keyboard,
trackpad or Mission Control) shows a small glass pill below the menu bar with
"Desktop N", or the app name on a full-screen Space.

## How it works

`spaces` posts a synthetic Dock swipe, the same kind of event a three-finger
trackpad swipe produces, with almost no travel and a high release velocity.
The Dock commits the switch with nothing left to animate. macOS 27 also checks
that the swipe carries a serialized trackpad (IOHID) record, so one is
attached. The approach follows [noswoosh](https://github.com/mmathys/noswoosh),
which documents it in depth.

It relies on undocumented event fields and a private SkyLight call (to know
which Space you're on), so a macOS update can break it.

Requires macOS 27 on Apple silicon. Trackpad swipes keep the native animation.
