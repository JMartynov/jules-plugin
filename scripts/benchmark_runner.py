import time

class WorkflowTimer:
    def __init__(self):
        self._starts = {}
        self._durations = {}

    def start(self, milestone_name: str) -> None:
        """Records start timestamp."""
        self._starts[milestone_name] = time.time()

    def stop(self, milestone_name: str) -> float:
        """Records end timestamp and returns elapsed duration in seconds."""
        if milestone_name not in self._starts:
            raise ValueError(f"Milestone '{milestone_name}' was not started.")
        if milestone_name in self._durations:
            raise ValueError(f"Milestone '{milestone_name}' was already stopped.")
            
        end_time = time.time()
        start_time = self._starts[milestone_name]
        duration = end_time - start_time
        
        self._durations[milestone_name] = duration
        # We don't remove from _starts in case we want to know when it started, 
        # but the task didn't specify. We'll leave it as is.
        return duration

    def get_duration(self, milestone_name: str) -> float:
        """Returns duration for completed milestone."""
        if milestone_name not in self._durations:
            if milestone_name in self._starts:
                raise ValueError(f"Milestone '{milestone_name}' has not been stopped yet.")
            raise ValueError(f"Milestone '{milestone_name}' was not started.")
        return self._durations[milestone_name]

    def summary(self) -> dict:
        """Returns dictionary of all milestones with their elapsed durations."""
        return self._durations.copy()

def format_duration(seconds: float) -> str:
    """Formats durations cleanly (e.g. '12.34s' or '1m 23s')."""
    if seconds < 60:
        return f"{seconds:.2f}s"
    else:
        minutes = int(seconds // 60)
        remaining_seconds = int(seconds % 60)
        return f"{minutes}m {remaining_seconds}s"
