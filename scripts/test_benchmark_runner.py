import unittest
import time
from scripts.benchmark_runner import WorkflowTimer, format_duration

class TestWorkflowTimer(unittest.TestCase):
    def setUp(self):
        self.timer = WorkflowTimer()

    def test_start_and_stop(self):
        self.timer.start("test_milestone")
        time.sleep(0.1)
        duration = self.timer.stop("test_milestone")
        
        self.assertGreaterEqual(duration, 0.1)
        self.assertLess(duration, 0.2)
        
        self.assertEqual(duration, self.timer.get_duration("test_milestone"))
        
    def test_stop_unstarted_milestone(self):
        with self.assertRaisesRegex(ValueError, "was not started"):
            self.timer.stop("nonexistent")
            
    def test_stop_already_stopped_milestone(self):
        self.timer.start("test_milestone")
        self.timer.stop("test_milestone")
        
        with self.assertRaisesRegex(ValueError, "was already stopped"):
            self.timer.stop("test_milestone")

    def test_get_duration_unstarted(self):
        with self.assertRaisesRegex(ValueError, "was not started"):
            self.timer.get_duration("nonexistent")
            
    def test_get_duration_unstopped(self):
        self.timer.start("test_milestone")
        with self.assertRaisesRegex(ValueError, "has not been stopped yet"):
            self.timer.get_duration("test_milestone")

    def test_summary(self):
        self.timer.start("m1")
        self.timer.start("m2")
        time.sleep(0.01)
        self.timer.stop("m1")
        time.sleep(0.01)
        self.timer.stop("m2")
        
        summary = self.timer.summary()
        self.assertIn("m1", summary)
        self.assertIn("m2", summary)
        self.assertGreater(summary["m2"], summary["m1"])


class TestFormatDuration(unittest.TestCase):
    def test_format_seconds(self):
        self.assertEqual(format_duration(12.345), "12.35s")
        self.assertEqual(format_duration(0.123), "0.12s")
        self.assertEqual(format_duration(59.999), "60.00s") # note: rounding to 60.00s is okay, maybe we should test formatting directly
        
    def test_format_minutes(self):
        self.assertEqual(format_duration(60.0), "1m 0s")
        self.assertEqual(format_duration(83.5), "1m 23s")
        self.assertEqual(format_duration(125.0), "2m 5s")
