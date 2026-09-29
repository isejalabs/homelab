"""Run with python3 scripts/test-mink-codex-hook.py."""

import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("adapter", Path(__file__).with_name("mink-codex-hook.py"))
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.cwd = Path(self.temp.name).resolve()
        (self.cwd / "a file.txt").write_text("hello\n")
        self.calls = []

    def runner(self, command, event, cwd):
        self.calls.append((command, event, cwd))
        return "Mink warning"

    def test_quoted_read(self):
        reads = adapter.shell_reads('cat "a file.txt"', self.cwd)
        self.assertEqual(reads, [("Read", {"file_path": str(self.cwd / "a file.txt")})])

    def test_ranged_read(self):
        reads = adapter.shell_reads('sed -n \'1,20p\' "a file.txt"', self.cwd)
        self.assertEqual(reads[0][1]["offset"], 1)

    def test_ambiguous_shell_is_not_interpreted(self):
        for command in ['cat $(whoami)', 'cat *.txt', 'cat x | head', 'cat x; touch y', 'sed -i s/a/b/ x', 'cat -n x']:
            with self.subTest(command=command):
                self.assertEqual(adapter.shell_reads(command, self.cwd), [])

    def test_read_outside_project_ignored(self):
        self.assertEqual(adapter.shell_reads("cat /etc/hosts", self.cwd), [])

    def test_multi_file_patch_and_rename(self):
        patch = '*** Begin Patch\n*** Add File: new.txt\n+hello\n*** Update File: old.txt\n*** Move to: moved.txt\n@@\n-before\n+after\n*** Delete File: deleted.txt\n*** End Patch\n'
        events = adapter.patch_writes(patch, self.cwd)
        self.assertEqual([Path(fields["file_path"]).name for _, fields in events], ['new.txt', 'moved.txt', 'old.txt', 'deleted.txt'])
        self.assertEqual(events[0][1]['content'], 'hello')
        self.assertEqual(events[1][1]['new_string'], 'after')

    def test_translation_and_warning_contract(self):
        result = adapter.handle({'cwd': str(self.cwd), 'hook_event_name': 'PreToolUse', 'tool_name': 'apply_patch', 'tool_input': {'command': '*** Begin Patch\n*** Add File: new.txt\n+hello\n*** End Patch\n'}}, self.runner)
        self.assertEqual(self.calls[0][0], 'pre-write')
        self.assertEqual(self.calls[0][1]['tool_name'], 'Write')
        self.assertEqual(result['hookSpecificOutput']['additionalContext'], 'Mink warning')

    def test_failed_command_not_logged(self):
        result = adapter.handle({'cwd': str(self.cwd), 'hook_event_name': 'PostToolUse', 'tool_name': 'Bash', 'tool_input': {'command': 'cat "a file.txt"'}, 'tool_response': {'exit_code': 1}}, self.runner)
        self.assertEqual(self.calls, [])
        self.assertEqual(result, {})

    def test_stop_is_nonblocking(self):
        result = adapter.handle({'cwd': str(self.cwd), 'hook_event_name': 'Stop'}, self.runner)
        self.assertEqual(self.calls[0][0], 'session-stop')
        self.assertEqual(result, {'systemMessage': 'Mink warning'})


if __name__ == '__main__':
    unittest.main()
