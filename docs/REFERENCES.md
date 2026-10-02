# References

Omarchy clipboard plugins that were tried (2026-10-01) before building this one, and what was
taken from each. It only records where each idea comes from; it is not part of the plugin.

Marketplace page: `https://plugins.omarchy.org/plugin.html?id=<id>`.

## Plugins we took something from

| Plugin | Author | What we took |
|---|---|---|
| [clipboard-history](https://github.com/alanfortlink/clipboard-history) | alanfortlink | **The base of this plugin** (fork, MIT). Polished UI, fuzzy search with tokens (`type:`, `app:`, `<2h`), the open/close effect, `Tab` to pin, clip details in the preview. Its active filter was too faint: improved. |
| [omarchy-clipboard](https://github.com/huyhuyvu01/omarchy-clipboard) | Huy Vu Quang | **Compact** mode (fonts and spacing), opening **at the mouse** while handling edges and monitors, **delete button** per row, clip **counter** in the search bar, clear-all with confirmation. |
| [reclip-omarchy](https://github.com/gameticharles/reclip-omarchy) (ReClip) | Charles Gameti | **Pause recording** (here: visible in the main UI), **action icons on hover**, extracting a **color palette** from an image (setting, off by default). Lesson: a single concept of pin. |
| [clipbook](https://github.com/protoavatar/clipbook) | protoavatar | **`F2` to edit** a clip in place, a **note per clip** (here: shown in the preview). |
| [omarchy-clipboard-plus](https://github.com/idr4n/omarchy-clipboard-plus) | Ivan Duran | **`Ctrl+E` to edit**, a **`Ctrl+.` actions menu** that changes with the clip type. |
| [omarchy-clipboard](https://github.com/htrnguyen-labs/omarchy-clipboard) | Ha Trong Nguyen | **Pins and history in two groups**, clearly separated. Lesson: never prune other plugins' files. |
| [clipbasket-omarchy](https://github.com/clipbasket/clipbasket-omarchy) | Clipbasket | **The settings UI** and its options, with Omarchy's native round `Toggle`. Lesson: having both "pin" and "saved" is confusing. |
| [omarchy-clipboard](https://github.com/MrShirini/omarchy-clipboard) | Amir Shirini | **Limits** in settings (max items, image cache, history size), resizable window (here: normal and compact), **pause button** in the main view. |
| [omarchy-clipboard-collector](https://github.com/jkarmel/omarchy-clipboard-collector) | jkarmel | (Not tried.) Reference for **merging** clips: joining several with a separator. |

## Tried, nothing to take

- [omapaste](https://github.com/pkayokay/omapaste) — Paul Kim: Paste.app-style card bar; not what we were after.
- [yank-omarchy-plugin](https://github.com/gran-software-solutions/yank-omarchy-plugin) — Gran Software Solutions: only the list UI, as a comparison.
- [omarchy-clipboard](https://github.com/iamcheyan/omarchy-clipboard) — iamcheyan: broken, did not open.
- [omarchy_clipboard](https://github.com/0-CYBERDYNE-SYSTEMS-0/omarchy_clipboard) — 0-CYBERDYNE-SYSTEMS-0.
- [omarchy-clipboard](https://github.com/uriakleahcim/omarchy-clipboard) — uriakleahcim: incomplete.
- [omarchy-clipboard-shelf](https://github.com/ReidenXerx/omarchy-clipboard-shelf) — ReidenXerx.
- [omarchy-snippets](https://github.com/prohner/omarchy-snippets) — Preston Rohner.
- [omarchy-snippets](https://github.com/shoxjaxon-atabayev/omarchy-snippets) — shoxjaxon.

## Lessons (what NOT to repeat)

- Data in **its own folder**; never read, rewrite or prune the files of `omarchy.clipboard` or of
  another plugin (several deleted other plugins' images).
- Reap only **our own** capture watchers, never any `capture.sh` / `capture.py`.
- Do not touch the user's config (`bindings.lua`, the Omarchy menu) unless asked.
- The open shortcut must work from a clean start, right after the shell restarts.
