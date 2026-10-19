import unittest
import json
import csv
import io
from telemetry_exporter import TelemetryExporter

class TestTelemetryExporter(unittest.TestCase):
    def setUp(self):
        self.exporter = TelemetryExporter()

    def test_add_record(self):
        self.exporter.add_record("cpu_usage", 45.2, {"host": "server-1"})
        self.assertEqual(len(self.exporter.records), 1)
        self.assertEqual(self.exporter.records[0]["metric"], "cpu_usage")
        self.assertEqual(self.exporter.records[0]["value"], 45.2)
        self.assertEqual(self.exporter.records[0]["tags"], {"host": "server-1"})
        self.assertIn("timestamp", self.exporter.records[0])

    def test_add_record_no_tags(self):
        self.exporter.add_record("memory_usage", 80.5)
        self.assertEqual(len(self.exporter.records), 1)
        self.assertEqual(self.exporter.records[0]["tags"], {})

    def test_to_json(self):
        self.exporter.add_record("disk_io", 12.3, {"device": "sda"})
        json_str = self.exporter.to_json()
        data = json.loads(json_str)
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]["metric"], "disk_io")
        self.assertEqual(data[0]["value"], 12.3)
        self.assertEqual(data[0]["tags"], {"device": "sda"})

    def test_to_csv(self):
        self.exporter.add_record("network_rx", 1024.0, {"interface": "eth0"})
        csv_str = self.exporter.to_csv()
        reader = csv.reader(io.StringIO(csv_str))
        rows = list(reader)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], ["timestamp", "metric", "value", "tags"])
        self.assertEqual(rows[1][1], "network_rx")
        self.assertEqual(rows[1][2], "1024.0")
        self.assertEqual(rows[1][3], '{"interface": "eth0"}')

    def test_clear(self):
        self.exporter.add_record("uptime", 3600.0)
        self.assertEqual(len(self.exporter.records), 1)
        self.exporter.clear()
        self.assertEqual(len(self.exporter.records), 0)

    def test_empty_records(self):
        json_str = self.exporter.to_json()
        self.assertEqual(json_str, "[]")

        csv_str = self.exporter.to_csv()
        self.assertEqual(csv_str.strip(), "timestamp,metric,value,tags")

if __name__ == '__main__':
    unittest.main()
