import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('file_preview', Path(__file__).resolve().parents[1] / 'scripts/file-preview.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FilePreviewTests(unittest.TestCase):
    def test_text_is_bounded_and_path_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'a " quoted.txt'
            path.write_text('a' * 10000)
            data = module.preview(str(path))
            self.assertEqual(data['bytes'], 10000)
            self.assertEqual(len(data['text']), 8192)
            self.assertTrue(data['truncated'])
            self.assertEqual(data['path'], str(path))

    def test_missing_file_and_folder(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(module.preview(directory)['kind'], 'Folder')
            self.assertIn('error', module.preview(directory + '/missing'))

    def test_special_file_is_not_read(self):
        with tempfile.TemporaryDirectory() as directory:
            path = directory + '/fifo.txt'
            os.mkfifo(path)
            self.assertEqual(module.preview(path)['kind'], 'Special file')

    def test_missing_media_tools_preserve_basic_metadata(self):
        with tempfile.NamedTemporaryFile(suffix='.mp4') as source:
            with patch.object(module, 'read_bounded', return_value=None):
                data = module.preview(source.name)
            self.assertEqual(data['mime'], 'video/mp4')
            self.assertIn('bytes', data)
            self.assertNotIn('thumbnail', data)

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'ffmpeg optional')
    def test_video_resolution_duration_and_thumbnail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = directory + '/clip.mkv'
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=red:s=160x90:d=1', '-c:v', 'ffv1', path], check=True, timeout=10)
            data = module.preview(path)
            self.assertEqual((data['width'], data['height']), (160, 90))
            self.assertAlmostEqual(data['duration'], 1, places=1)
            self.assertTrue(data['thumbnail'].startswith('data:image/jpeg;base64,'))

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'ffmpeg optional')
    def test_audio_details(self):
        with tempfile.TemporaryDirectory() as directory:
            path = directory + '/audio.wav'
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'sine=duration=1', path], check=True, timeout=10)
            data = module.preview(path)
            self.assertAlmostEqual(data['duration'], 1, places=1)
            self.assertIn('44100 Hz', data['audio'])
            self.assertNotIn('thumbnail', data)

    def test_generic_binary_not_shown_as_text(self):
        with tempfile.NamedTemporaryFile(suffix='.txt') as source:
            source.write(b'abc\x00def')
            source.flush()
            self.assertNotIn('text', module.preview(source.name))


def chunk(ctype, body):
    import struct
    import zlib
    return struct.pack('>I', len(body)) + ctype + body + struct.pack('>I', zlib.crc32(ctype + body))


def png(*extra):
    import struct
    import zlib
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 0, 0, 0, 0))
    return b'\x89PNG\r\n\x1a\n' + ihdr + b''.join(extra) + chunk(b'IDAT', zlib.compress(b'\x00\x80')) + chunk(b'IEND', b'')


class CopiedPngTests(unittest.TestCase):
    def decoders_see(self, path):
        """Run preview() with fake decoders; return what each one was given."""
        seen = []

        def fake(args, limit, timeout=None, max_memory=None):
            source = args[args.index('-i') + 1] if '-i' in args else args[-1]
            seen.append((args[0], source, Path(source).read_bytes(), max_memory))
            return None
        with patch.object(module, 'read_bounded', side_effect=fake):
            data = module.preview(path)
        return data, seen

    def test_copied_png_reaches_decoders_stripped(self):
        import zlib
        bomb = chunk(b'zTXt', b'k\x00\x00' + zlib.compress(b'\x00' * (1024 * 1024)))
        with tempfile.TemporaryDirectory() as directory:
            for name in ('shot.png', 'disguised.mp4'):  # PNG por contenido, sea cual sea la extensión
                path = os.path.join(directory, name)
                Path(path).write_bytes(png(bomb))
                data, seen = self.decoders_see(path)
                self.assertEqual([s[0] for s in seen], ['ffprobe'])
                tool, source, content, memory = seen[0]
                self.assertNotEqual(source, path)
                self.assertEqual(content, png())
                self.assertEqual(memory, module.DECODER_MEMORY)
                self.assertFalse(os.path.exists(source))  # la copia limpia se borra
                self.assertEqual(data['bytes'], len(png(bomb)))

    def test_malformed_png_gets_metadata_but_no_decoder(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, 'broken.png')
            Path(path).write_bytes(png()[:-12])
            data, seen = self.decoders_see(path)
            self.assertEqual(seen, [])
            self.assertEqual(data['mime'], 'image/png')
            self.assertNotIn('thumbnail', data)

    def test_other_media_is_decoded_in_place_under_the_memory_cap(self):
        with tempfile.NamedTemporaryFile(suffix='.mp4') as source:
            source.write(b'not a png')
            source.flush()
            data, seen = self.decoders_see(source.name)
            self.assertEqual(seen[0][1], source.name)
            self.assertEqual(seen[0][3], module.DECODER_MEMORY)

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'ffmpeg optional')
    def test_real_png_with_metadata_still_gets_a_thumbnail(self):
        import zlib
        with tempfile.TemporaryDirectory() as directory:
            plain = os.path.join(directory, 'plain.png')
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=red:s=160x90', '-frames:v', '1', plain], check=True, timeout=10)
            raw = Path(plain).read_bytes()
            bomb = chunk(b'zTXt', b'k\x00\x00' + zlib.compress(b'\x00' * (8 * 1024 * 1024)))
            path = os.path.join(directory, 'dirty.png')
            Path(path).write_bytes(raw[:33] + bomb * 4 + raw[33:])
            data = module.preview(path)
            self.assertEqual((data['width'], data['height']), (160, 90))
            self.assertTrue(data['thumbnail'].startswith('data:image/jpeg;base64,'))


class DecoderMemoryCapTests(unittest.TestCase):
    def test_child_over_the_cap_fails_and_under_it_works(self):
        import sys
        grab = [sys.executable, '-c', 'b = bytearray(512 * 1024 * 1024); print("ok")']
        self.assertIsNone(module.read_bounded(grab, 1024, timeout=10, max_memory=256 * 1024 * 1024))
        self.assertEqual(module.read_bounded(grab, 1024, timeout=10, max_memory=2 * 1024 * 1024 * 1024), b'ok\n')
