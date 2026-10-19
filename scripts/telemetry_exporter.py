import json
import csv
import io
import time

class TelemetryExporter:
    def __init__(self):
        self.records = []

    def add_record(self, metric_name: str, value: float, tags: dict = None) -> None:
        """Records a metric data point with timestamp."""
        record = {
            "timestamp": time.time(),
            "metric": metric_name,
            "value": value,
            "tags": tags if tags is not None else {}
        }
        self.records.append(record)

    def to_json(self) -> str:
        """Serializes all recorded metrics into formatted JSON string."""
        return json.dumps(self.records, indent=2)

    def to_csv(self) -> str:
        """Formats all recorded metrics into CSV format with header timestamp,metric,value,tags."""
        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(["timestamp", "metric", "value", "tags"])
        for record in self.records:
            tags_str = json.dumps(record["tags"])
            writer.writerow([record["timestamp"], record["metric"], record["value"], tags_str])
        return output.getvalue()

    def clear(self) -> None:
        """Resets all recorded metrics."""
        self.records = []
