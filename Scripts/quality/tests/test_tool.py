import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "tool"

FAKE_GIT = """#!/bin/sh
case " $* " in
*" --local-env-vars "*) exec "$REAL_GIT" "$@" ;;
*" clone "*)
    env | grep '^GIT_' > "$SEEN/clone" || true
    for last; do :; done
    mkdir -p "$last" ;;
*" HEAD "*) echo "$PINNED_COMMIT" ;;
esac
"""

FAKE_SWIFT = """#!/bin/sh
env | grep '^GIT_' >> "$SEEN/swift" || true
case " $* " in
*" --show-bin-path "*) echo "$BUILT" ;;
*)
    mkdir -p "$BUILT"
    printf '#!/bin/sh\\necho built\\n' > "$BUILT/swiftformat"
    chmod +x "$BUILT/swiftformat" ;;
esac
"""


class FetchingFromInsideAGitHook(unittest.TestCase):
    def setUp(self):
        self.scratch = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.scratch)
        self.seen = self.scratch / "seen"
        self.seen.mkdir()
        fakes = self.scratch / "bin"
        fakes.mkdir()
        for name, script in (("git", FAKE_GIT), ("swift", FAKE_SWIFT)):
            (fakes / name).write_text(script)
            (fakes / name).chmod(0o755)
        pinned = re.search(r"^SWIFTFORMAT_COMMIT=(\w+)$", TOOL.read_text(), re.MULTILINE)
        self.environment = {
            "PATH": f"{fakes}:/usr/bin:/bin",
            "QUALITY_TOOLS_DIR": str(self.scratch / "tools"),
            "SEEN": str(self.seen),
            "BUILT": str(self.scratch / "built"),
            "PINNED_COMMIT": pinned.group(1),
            "REAL_GIT": shutil.which("git"),
            "GIT_INDEX_FILE": str(self.scratch / "caller-index"),
            "GIT_DIR": str(self.scratch / "caller.git"),
            "GIT_WORK_TREE": str(self.scratch),
        }

    def fetch(self):
        return subprocess.run([str(TOOL), "swiftformat", "--version"], env=self.environment,
                              capture_output=True, text=True, check=False)

    def test_the_tool_is_fetched_and_run(self):
        result = self.fetch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "built")

    def test_the_clone_never_sees_the_callers_repository(self):
        self.fetch()
        self.assertEqual((self.seen / "clone").read_text(), "")

    def test_the_build_never_sees_the_callers_repository(self):
        self.fetch()
        self.assertEqual((self.seen / "swift").read_text(), "")


if __name__ == "__main__":
    unittest.main()
