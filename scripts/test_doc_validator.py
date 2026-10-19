import os
import tempfile
import unittest
from doc_validator import DocValidator

class TestDocValidator(unittest.TestCase):
    def setUp(self):
        self.validator = DocValidator()

    def test_validate_links(self):
        text = "This is a [valid link](http://example.com) and an [empty link]() and a [bad link](http:// example.com)"
        issues = self.validator.validate_links(text)
        self.assertEqual(len(issues), 2)
        
        empty_issues = [i for i in issues if i['type'] == 'empty_target']
        self.assertEqual(len(empty_issues), 1)
        self.assertEqual(empty_issues[0]['label'], 'empty link')
        
        syntax_issues = [i for i in issues if i['type'] == 'syntax_error']
        self.assertEqual(len(syntax_issues), 1)
        self.assertEqual(syntax_issues[0]['label'], 'bad link')

    def test_validate_file_references(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a target file
            target_path = os.path.join(tmpdir, "target.md")
            with open(target_path, "w") as f:
                f.write("target")
                
            text = "Here is an [existing file](target.md) and a [missing file](missing.md) and an [anchor](#anchor) and a [url](https://example.com)"
            
            issues = self.validator.validate_file_references(text, base_dir=tmpdir)
            self.assertEqual(len(issues), 1)
            self.assertEqual(issues[0]['type'], 'missing_file')
            self.assertEqual(issues[0]['target'], 'missing.md')

    def test_generate_report(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            file1 = os.path.join(tmpdir, "file1.md")
            with open(file1, "w") as f:
                f.write("Valid link: [example](http://example.com)")
                
            file2 = os.path.join(tmpdir, "file2.md")
            with open(file2, "w") as f:
                f.write("Empty link: [empty]() and missing file: [missing](missing.md)")
                
            report = self.validator.generate_report([file1, file2])
            
            self.assertEqual(report['total_files'], 2)
            self.assertEqual(report['valid_files'], 1)
            self.assertIn(file2, report['issues_found'])
            self.assertEqual(len(report['issues_found'][file2]), 2)
            self.assertNotIn(file1, report['issues_found'])

if __name__ == '__main__':
    unittest.main()
