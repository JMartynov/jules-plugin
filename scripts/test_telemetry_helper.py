import unittest
import json
import os
from scripts.telemetry_helper import export_telemetry_json

class TestTelemetryHelper(unittest.TestCase):
    def test_export_telemetry_json(self):
        data = {"key": "value"}
        filepath = "test_output.json"
        
        # Ensure file does not exist
        if os.path.exists(filepath):
            os.remove(filepath)
            
        success = export_telemetry_json(data, filepath)
        self.assertTrue(success)
        self.assertTrue(os.path.exists(filepath))
        
        with open(filepath, 'r') as f:
            loaded_data = json.load(f)
            
        self.assertEqual(data, loaded_data)
        
        # Clean up
        os.remove(filepath)

if __name__ == '__main__':
    unittest.main()
