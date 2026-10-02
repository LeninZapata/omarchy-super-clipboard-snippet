# Changelog — Super Clipboard-Snippet

> What changed, by version (newest on top; the last 10 are kept).

## 0.1.0 - 2026-10-01 22:28
---
- [feature] Two tabs, Clipboard and Snippets, switched with ← / →
- [feature] Pins in their own group on top, with a fixed number and Ctrl+1…9 to paste them
- [feature] Type filters next to the search bar, navigable with Ctrl+F
- [feature] Edit a clip in place with F2 / Ctrl+E, and a note per clip with Ctrl+M
- [feature] Ctrl+. actions menu that depends on the clip type (text transforms, colors, OCR, links)
- [feature] Clear the history with a button by typing the confirmation word
- [feature] Visible pause button for recording, and row actions on mouse hover
- [feature] Settings page: limits for count, age, image cache and history size, close on outside click, delete confirmation, OCR/QR
- [feature] Normal or compact size, opening at the center or at the mouse
- [feature] Interface in English (default) and Spanish
- [feature] Snippets with a name, a slug and Markdown text with date and time variables (Ctrl+K)
- [feature] Quick snippets popup at the mouse to paste from any app
- [feature] Global shortcuts configurable in Settings, registered in Hyprland without touching bindings.lua
- [feature] Import and export of snippets and settings
- [new] Fork of alanfortlink/clipboard-history with its own data folder, and docs/REFERENCES.md
- [new] Full README with screenshots, uninstall instructions and a marketplace preview image
- [update] A single window with a dimmed background and its own faster fade
- [update] Under each clip only the time and size; the details stay in the preview
- [fix] Pins are no longer lost to the limits or when clearing the history
- [fix] Copied text is sent to wl-copy over stdin, never as a process argument other users could read
- [fix] The snippet preview and every text that shows clip or snippet content render as plain text, so no remote image can load (and leak {clipboard})
