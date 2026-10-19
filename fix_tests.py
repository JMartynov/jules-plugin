with open("scripts/test_workflow_engine.py", "r") as f:
    content = f.read()

content = content.replace("if __name__ == '__main__':\n    unittest.main()", "")
content += "\nif __name__ == '__main__':\n    unittest.main()\n"

with open("scripts/test_workflow_engine.py", "w") as f:
    f.write(content)
