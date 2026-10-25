# Changelog — Super Clipboard-Snippet

> What changed, by version (newest on top; the last 10 are kept).

## 0.2.11 - 2026-10-25 12:02
---
- [feature] The selected or hovered clip shows its detected type next to its age and size, written as the search filter (`type:color`, `type:json`…) so it can be typed as-is to filter by it

## 0.2.10 - 2026-10-25 08:34
---
- [fix] Pasting a text clip that looks like an email (`From:` / `To:` / `Subject:` headers) pasted nothing: it is now always offered as plain text instead of the type wl-copy guessed from its content (`message/rfc822`)

## 0.2.9 - 2026-10-25 08:29
---
- [feature] Color clips (`#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `hsl()`) show a small swatch of the color right after their text in the list

## 0.2.8 - 2026-10-16 13:26
---
- [fix] Copied images are stored only when their bytes are PNG, JPEG, GIF, WebP, BMP or TIFF, whatever type the source app advertises: an SVG offered as `image/jpeg` (which could embed an unsanitized PNG) is no longer kept
- [fix] Stored images that are not one of those formats by content are removed when the shell starts

## 0.2.7 - 2026-10-15 07:47
---
- [fix] QR decoding and OCR (zbarimg, tesseract) run under the same 1 GiB memory cap as the file preview decoders, at capture and in the OCR backfill script
- [fix] Multi-page TIFFs are stored and previewed but skip QR/OCR: only the first page's size was checked, while tesseract decodes every page

## 0.2.6 - 2026-10-14 21:15
---
- [fix] A PNG copied as a file is previewed from a copy stripped of its metadata chunks, never from the original, so ffmpeg cannot expand its compressed text into gigabytes
- [fix] Every preview decoder (ffprobe, ffmpeg, pdftoppm, pdfinfo) runs under a 1 GiB memory cap: a file that tries to use more just gets no thumbnail

## 0.2.5 - 2026-10-14 08:50
---
- [fix] History, snippets, pause state and settings are owner-only: the plugin's folders are set to 700 and their files to 600 at shell start, existing ones included, and missing files are created private before anything is written
- [fix] Captured images, the OCR backfill and snippet/settings exports are written owner-only too

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
