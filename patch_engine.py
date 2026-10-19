import re

with open("scripts/workflow_engine.py", "r") as f:
    content = f.read()

loop_old = """                    fut = executor.submit(self._execute_single_task, task, dry_run)
                    in_flight[fut] = tid

                if not in_flight:
                    break

                done, _ = concurrent.futures.wait("""

loop_new = """                    fut = executor.submit(self._execute_single_task, task, dry_run)
                    in_flight[fut] = tid

                if not in_flight and not ts.is_active():
                    break
                elif not in_flight:
                    # we might have completed tasks that unblocked something, 
                    # but if there are no more tasks running and we still have active nodes, we might be stuck
                    # BUT with `resume`, we immediately marked some as done without submitting them.
                    # so ts.get_ready() could yield more in the next loop.
                    # Wait, if we continue to the top of the while loop, it'll fetch the next ready nodes!
                    continue

                done, _ = concurrent.futures.wait("""

content = content.replace(loop_old, loop_new)

with open("scripts/workflow_engine.py", "w") as f:
    f.write(content)

