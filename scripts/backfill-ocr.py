#!/usr/bin/env python3
"""Backfill OCR text for image entries already in clipboard history.

Run manually (optional): python3 scripts/backfill-ocr.py [--lang eng]
Images are not re-decoded unless their entry has no `ocr` field; the history
file is updated in place (atomic). Requires tesseract for the chosen lang.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import capture  # noqa: E402  (image_size / MAX_PARSE_PIXELS shared with the daemon)

STATE = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "omarchy", "super-clipboard-snippet", "history.json"
)


def ocr(path, lang):
    try:
        r = subprocess.run(
            ["tesseract", path, "stdout", "-l", lang],
            capture_output=True, timeout=30, preexec_fn=capture.limit_memory(capture.DECODER_MEMORY)
        )
        if r.returncode != 0:
            return None
        text = "\n".join(l.strip() for l in r.stdout.decode("utf-8", "replace").splitlines() if l.strip())
        return text[:4000] or None
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", default="eng")
    ap.add_argument("--force", action="store_true", help="re-OCR even when ocr exists")
    args = ap.parse_args()

    if shutil.which("tesseract") is None:
        sys.exit("tesseract not found — install with: omarchy pkg add tesseract tesseract-data-" + args.lang)

    if not os.path.exists(STATE):
        sys.exit("no history at " + STATE)

    with open(STATE) as f:
        history = json.load(f)

    changed = 0
    for entry in history:
        if entry.get("type") != "image" or not entry.get("path"):
            continue
        if entry.get("ocr") and not args.force:
            continue
        if not os.path.exists(entry["path"]):
            continue
        # Same guard as the capture daemon (capture.can_parse): known dimensions
        # under the pixel cap, and a TIFF only with a single page.
        with open(entry["path"], "rb") as f:
            data = f.read(capture.MAX_IMAGE_BYTES + 1)
        mime = entry.get("mime") or "image/png"
        if len(data) > capture.MAX_IMAGE_BYTES or not capture.can_parse(data, mime):
            print(f"  - {entry['id']}: skipped (size {capture.image_size(data, mime) or 'unknown'})")
            continue
        text = ocr(entry["path"], args.lang)
        if text:
            entry["ocr"] = text
            changed += 1
            print(f"  + {entry['id']}: {text[:60]!r}…")

    if changed:
        tmp = STATE + ".tmp"
        # El historial guarda texto copiado: solo lo lee su dueño (600).
        with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
            json.dump(history, f, indent=1)
            f.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, STATE)
    print(f"OCR'd {changed} image(s); {sum(1 for e in history if e.get('ocr'))} total with OCR text")


if __name__ == "__main__":
    main()
