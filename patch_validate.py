import re

with open("scripts/workflow_engine.py", "r") as f:
    content = f.read()

# Change validate logic. Static order calls ts.prepare() internally in some python versions.
validate_logic = """    def validate(self) -> List[str]:
        \"\"\"Validates acyclicity using TopologicalSorter and returns static topological order.\"\"\"
        if hasattr(self, "_validated_order"):
            return self._validated_order
            
        ts = graphlib.TopologicalSorter()
        for tid, task in self.tasks.items():
            for dep in task.depends_on:
                if dep not in self.tasks:
                    raise ValueError(f"Task '{tid}' depends on non-existent task '{dep}'.")
                if dep == tid:
                    raise ValueError(f"Task '{tid}' cannot depend on itself.")
            ts.add(tid, *task.depends_on)
        try:
            order = tuple(ts.static_order())
            self._validated_order = list(order)
            return self._validated_order
        except graphlib.CycleError as e:
            cycle_path = " -> ".join(e.args[1])
            raise RuntimeError(f"Workflow contains a dependency cycle: {cycle_path}") from e"""

content = re.sub(r'    def validate\(self\) -> List\[str\]:.*?(?=    def get_execution_waves)', validate_logic + "\n\n", content, flags=re.DOTALL)

with open("scripts/workflow_engine.py", "w") as f:
    f.write(content)
