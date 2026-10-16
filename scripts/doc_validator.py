import os
import re

class DocValidator:
    def validate_links(self, text: str) -> list:
        """
        Extracts markdown links [label](target) and identifies syntax errors or empty targets.
        """
        issues = []
        # Pattern to match [label](target)
        link_pattern = re.compile(r'\[([^\]]*)\]\(([^)]*)\)')
        
        for match in link_pattern.finditer(text):
            label = match.group(1)
            target = match.group(2)
            
            if not target.strip():
                issues.append({
                    'type': 'empty_target',
                    'label': label,
                    'context': match.group(0)
                })
            elif " " in target.strip():
                # Link targets should typically not contain spaces without encoding or <>
                issues.append({
                    'type': 'syntax_error',
                    'label': label,
                    'target': target,
                    'context': match.group(0)
                })
                
        return issues

    def validate_file_references(self, text: str, base_dir: str = ".") -> list:
        """
        Checks if local relative file links exist.
        """
        issues = []
        link_pattern = re.compile(r'\[([^\]]*)\]\(([^)]*)\)')
        
        for match in link_pattern.finditer(text):
            target = match.group(2).strip()
            
            # Skip empty, remote URLs, mailto, or anchors
            if not target or target.startswith(('http://', 'https://', 'mailto:', '#')):
                continue
                
            # Remove anchor part if present
            target_path = target.split('#')[0]
            if not target_path:
                continue
                
            full_path = os.path.join(base_dir, target_path)
            if not os.path.exists(full_path):
                issues.append({
                    'type': 'missing_file',
                    'target': target,
                    'path': full_path,
                    'context': match.group(0)
                })
                
        return issues

    def generate_report(self, filepaths: list) -> dict:
        """
        Validates a list of markdown file paths and returns a summary dict with
        total_files, valid_files, and issues_found.
        """
        report = {
            'total_files': len(filepaths),
            'valid_files': 0,
            'issues_found': {}
        }
        
        valid_count = 0
        for filepath in filepaths:
            if not os.path.exists(filepath):
                report['issues_found'][filepath] = [{'type': 'file_not_found', 'path': filepath}]
                continue
                
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    text = f.read()
            except Exception as e:
                report['issues_found'][filepath] = [{'type': 'read_error', 'error': str(e)}]
                continue
                
            base_dir = os.path.dirname(filepath)
            if not base_dir:
                base_dir = "."
                
            link_issues = self.validate_links(text)
            file_issues = self.validate_file_references(text, base_dir)
            
            all_issues = link_issues + file_issues
            if all_issues:
                report['issues_found'][filepath] = all_issues
            else:
                valid_count += 1
                
        report['valid_files'] = valid_count
        return report
