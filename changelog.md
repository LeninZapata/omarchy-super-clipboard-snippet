# Changelog — Super Clipboard-Snippet

> What changed, by version (newest on top; the last 10 are kept).

## 0.2.4 - 2026-10-13 23:14
---
- [fix] Copied PNG images are stored without their metadata chunks (text, ICC profile, Exif): the shell's image decoder inflated compressed text before any size limit, so a small PNG could make it allocate gigabytes. Pixels are untouched; malformed PNGs are not stored
- [fix] Images saved by earlier versions get the same cleanup when the shell starts, and no thumbnail or preview loads until it finishes

## 0.2.3 - 2026-10-13 07:48
---
- [fix] No native Qt text input anywhere: every field (quick snippets search, actions filter, clear-history prompt, clip/note editor, snippet name, slug and body) is the plugin's own PlainEdit, so no field reads foreign clipboard text, open or hidden
- [new] PlainEdit.qml + Editing.js: single and multi-line editing with cursor, selection (keyboard and mouse), word moves, wrapping, undo/redo
- [update] Ctrl+V inside a field pastes the latest text clip from the history; Ctrl+C / Ctrl+X copy the selection
- [update] README: how the text fields work

## 0.2.2 - 2026-10-13 00:15
---
- [fix] Editable fields (quick snippets search, actions filter, clear-history prompt, clip and snippet editors) only exist while their panel is open: a hidden but live text field re-read foreign clipboard text on every change, with no size or time limit
- [update] The preview pane is only created while the window is visible

## 0.2.1 - 2026-10-12 07:13
---
- [fix] Old pins no longer vanish from the list once the history grows past the row cap (`maxRows`); they were kept in the history but cut from the view

## 0.2.0 - 2026-10-02 12:15
---
- [feature] "Hide the content preview" setting: only the list, in a narrower window, with the type filters on their own line under the search
- [feature] Zen mode (sub-option of the above): one-line rows, icons instead of labels, a thinner tab underline, filters hidden until Ctrl+F, and smaller, dimmer key hints that light up on hover
- [feature] In zen mode the selected row shows its time and size at the right edge, over a fade
- [feature] Ctrl+S opens and closes Settings (Ctrl+, still works), and is shown in the key hints
- [update] The "Appearance" settings group is now "Layout"
- [update] Key hints at the bottom wrap to a second line when they do not fit
- [update] README: sections and screenshots for zen mode, pausing and clearing the history

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
