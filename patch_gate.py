import re

with open("bin/jules-gate", "r") as f:
    content = f.read()

old_usage = "  workflow <validate|run|waves> <file> [options] Validate or execute DAG task workflows."
new_usage = "  workflow <validate|run|waves|graph> <file> [options] Validate, execute, or visualize DAG task workflows (supports --resume)."

content = content.replace(old_usage, new_usage)

with open("bin/jules-gate", "w") as f:
    f.write(content)
