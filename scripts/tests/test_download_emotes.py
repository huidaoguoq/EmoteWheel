import hashlib
from io import BytesIO
from pathlib import Path
import sys
import unittest

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from download_emotes import matches_data, pixel_sha256


def png(pixels, size=(2, 1), compression=0):
    image = Image.new("RGBA", size)
    image.putdata(pixels)
    buffer = BytesIO()
    image.save(buffer, format="PNG", compress_level=compression)
    return buffer.getvalue()


class ImageIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.colors = [(20, 40, 60, 128), (90, 80, 70, 0)]
        self.original = png(self.colors)
        self.manifest = {
            "sha256": hashlib.sha256(self.original).hexdigest(),
            "pixelSha256": pixel_sha256(self.original),
        }

    def test_original_file(self):
        self.assertTrue(matches_data(self.original, self.manifest))

    def test_lossless_recompression(self):
        compressed = png(self.colors, compression=9)
        self.assertNotEqual(self.original, compressed)
        self.assertTrue(matches_data(compressed, self.manifest))

    def test_invisible_rgb_changes(self):
        optimized = png([self.colors[0], (0, 0, 0, 0)], compression=9)
        self.assertTrue(matches_data(optimized, self.manifest))

    def test_visible_color_change_rejected(self):
        changed = png([(21, 40, 60, 128), self.colors[1]])
        self.assertFalse(matches_data(changed, self.manifest))

    def test_alpha_change_rejected(self):
        changed = png([(20, 40, 60, 129), self.colors[1]])
        self.assertFalse(matches_data(changed, self.manifest))

    def test_different_dimensions_rejected(self):
        self.assertFalse(matches_data(png(self.colors, size=(1, 2)), self.manifest))

    def test_invalid_content_rejected(self):
        self.assertFalse(matches_data(b"<html>upstream unavailable</html>", self.manifest))
        self.assertFalse(matches_data(self.original[:20], self.manifest))


if __name__ == "__main__":
    unittest.main()
