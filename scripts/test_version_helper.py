import unittest
from scripts.version_helper import get_plugin_version

class TestVersionHelper(unittest.TestCase):
    def test_get_plugin_version(self):
        self.assertEqual(get_plugin_version(), '3.1.0')

if __name__ == '__main__':
    unittest.main()
