import os
import subprocess
import sys
import tempfile
import unittest


class WatcherInputTests(unittest.TestCase):
    def helper(self, stdin, timeout=0.2):
        return subprocess.Popen(
            [sys.executable, "-c", """
import capture
import sys
import tracemalloc
tracemalloc.start()
drain = capture.drain_stdin
capture.drain_stdin = lambda: drain(timeout=float(sys.argv[1]))
capture.list_types = lambda: print('probed') or []
capture.main()
assert tracemalloc.get_traced_memory()[1] < 1024 * 1024
""", str(timeout)], stdin=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def finish(self, proc, expected, payload=None):
        try:
            out, err = proc.communicate(input=payload, timeout=8)
            self.assertEqual(proc.returncode, 0, err.decode())
            self.assertEqual(out, expected)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()

    def test_large_payload_is_discarded_without_accumulation(self):
        with tempfile.TemporaryFile() as source:
            source.truncate(64 * 1024 * 1024)
            self.finish(self.helper(source, timeout=5), b"probed\n")

    def test_finite_pipe_still_probes(self):
        self.finish(self.helper(subprocess.PIPE, timeout=5), b"probed\n",
                    payload=b"clipboard content\n" * 16384)

    def test_stalled_pipe_exits_without_probing(self):
        reader, writer = os.pipe()
        try:
            with os.fdopen(reader, "rb") as source:
                self.finish(self.helper(source), b"")
        finally:
            os.close(writer)

    def test_endless_source_exits_without_probing(self):
        with open('/dev/zero', 'rb') as source:
            self.finish(self.helper(source), b"")

    def test_empty_input_still_probes(self):
        self.finish(self.helper(subprocess.DEVNULL), b"probed\n")


sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import struct  # noqa: E402
import zlib  # noqa: E402
import capture  # noqa: E402


def chunk(ctype, body):
    return struct.pack(">I", len(body)) + ctype + body + struct.pack(">I", zlib.crc32(ctype + body))


def png(*extra):
    """A 1x1 grey PNG with `extra` chunks between IHDR and IDAT."""
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0))
    idat = chunk(b"IDAT", zlib.compress(b"\x00\x80"))
    return capture.PNG_SIGNATURE + ihdr + b"".join(extra) + idat + chunk(b"IEND", b"")


class SanitizePngTests(unittest.TestCase):
    def test_metadata_chunks_are_dropped_and_pixels_kept(self):
        bomb = zlib.compress(b"\x00" * (4 * 1024 * 1024))
        dirty = png(chunk(b"zTXt", b"k\x00\x00" + bomb), chunk(b"iTXt", b"k\x00\x01\x00\x00\x00" + bomb),
                    chunk(b"iCCP", b"p\x00\x00" + bomb), chunk(b"tEXt", b"Comment\x00hi"),
                    chunk(b"eXIf", b"MM\x00*"), chunk(b"gAMA", struct.pack(">I", 45455)))
        clean = capture.sanitize_png(dirty)
        self.assertEqual(clean, png(chunk(b"gAMA", struct.pack(">I", 45455))))
        for ctype in (b"zTXt", b"iTXt", b"iCCP", b"tEXt", b"eXIf"):
            self.assertNotIn(ctype, clean)

    def test_clean_png_is_unchanged(self):
        self.assertEqual(capture.sanitize_png(png()), png())

    def test_trailing_bytes_after_iend_are_dropped(self):
        self.assertEqual(capture.sanitize_png(png() + b"junk"), png())

    def test_malformed_pngs_are_rejected(self):
        good = png()
        bad_crc = bytearray(good)
        bad_crc[-5] ^= 1  # dentro del CRC de IEND
        self.assertIsNone(capture.sanitize_png(bytes(bad_crc)))
        self.assertIsNone(capture.sanitize_png(good[:-12]))  # sin IEND
        self.assertIsNone(capture.sanitize_png(good[:-6]))  # fragmento cortado
        self.assertIsNone(capture.sanitize_png(b"\xff\xd8\xff" + good[3:]))  # no es PNG
        no_idat = capture.PNG_SIGNATURE + good[8:33] + chunk(b"IEND", b"")
        self.assertIsNone(capture.sanitize_png(no_idat))
        not_ihdr_first = capture.PNG_SIGNATURE + chunk(b"tEXt", b"a\x00b") + good[8:]
        self.assertIsNone(capture.sanitize_png(not_ihdr_first))

    def test_image_dir_pass_rewrites_by_content_and_removes_broken(self):
        with tempfile.TemporaryDirectory() as d:
            files = {
                "dirty.png": png(chunk(b"zTXt", b"k\x00\x00" + zlib.compress(b"x" * 1000))),
                "disguised.jpg": png(chunk(b"tEXt", b"a\x00b")),  # PNG por contenido
                "clean.png": png(),
                "broken.png": png()[:-12],
                "photo.jpg": b"\xff\xd8\xff\xe0 not a png",
            }
            for name, data in files.items():
                with open(os.path.join(d, name), "wb") as f:
                    f.write(data)
            self.assertEqual(capture.sanitize_image_dir(d), (2, 1))
            read = lambda n: open(os.path.join(d, n), "rb").read()
            self.assertEqual(read("dirty.png"), png())
            self.assertEqual(read("disguised.jpg"), png())
            self.assertEqual(read("clean.png"), png())
            self.assertFalse(os.path.exists(os.path.join(d, "broken.png")))
            self.assertEqual(read("photo.jpg"), files["photo.jpg"])

    def test_capture_stores_the_stripped_png(self):
        dirty = png(chunk(b"zTXt", b"k\x00\x00" + zlib.compress(b"x" * 1000)))
        out = []
        with tempfile.TemporaryDirectory() as d:
            saved = (capture.IMAGE_DIR, capture.read_clipboard, capture.emit, capture.decode_ocr,
                     os.environ.get("CLIPBOARD_QR"))
            capture.IMAGE_DIR = d
            capture.read_clipboard = lambda mime, limit: dirty
            capture.emit = out.append
            capture.decode_ocr = lambda path, lang: None
            os.environ["CLIPBOARD_QR"] = "0"
            try:
                self.assertTrue(capture.capture_image(["image/webp"], "app"))
            finally:
                capture.IMAGE_DIR, capture.read_clipboard, capture.emit, capture.decode_ocr = saved[:4]
                if saved[4] is None:
                    os.environ.pop("CLIPBOARD_QR", None)
                else:
                    os.environ["CLIPBOARD_QR"] = saved[4]
            self.assertEqual(len(out), 1)
            self.assertEqual(out[0]["mime"], "image/png")
            self.assertTrue(out[0]["path"].endswith(".png"))
            self.assertEqual(open(out[0]["path"], "rb").read(), png())
            self.assertEqual(out[0]["bytes"], len(png()))


class PrivateFilesTests(unittest.TestCase):
    def test_capture_runs_with_owner_only_umask(self):
        with tempfile.TemporaryDirectory() as d:
            out = subprocess.run(
                [sys.executable, "-c", "import capture, os, sys; sys.argv = ['capture.py', 'sanitize-images'];"
                 " capture.main(); print(oct(os.umask(0)))"],
                cwd=os.path.join(os.path.dirname(__file__), ".."), capture_output=True, text=True,
                env=dict(os.environ, XDG_STATE_HOME=d))
            self.assertEqual(out.stdout.strip(), "0o77", out.stderr)

    def test_stored_png_is_owner_only(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "a.png")
            old = os.umask(0o022)
            try:
                capture.write_atomic(path, png())
            finally:
                os.umask(old)
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
