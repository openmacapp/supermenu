#!/usr/bin/env python3
"""Install repository hooks without replacing core.hooksPath or existing hooks."""

from pathlib import Path
import subprocess


git_dir = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], text=True).strip())
hooks = git_dir / "hooks"
marker = "# SuperMenu privacy guard"
scripts = {}
guard = hooks / "privacy_guard.py"
guard_marker = "# SuperMenu privacy guard implementation"
if guard.exists() and guard_marker not in guard.read_text():
    raise SystemExit("Existing privacy_guard.py was preserved; integrate it explicitly before installing.")
scripts[guard] = Path(__file__).with_name("privacy_guard.py").read_text()
for hook, mode in {"pre-commit": "staged", "commit-msg": "message", "pre-push": "pre-push"}.items():
    path = hooks / hook
    if path.exists() and marker not in path.read_text():
        raise SystemExit("Existing " + hook + " was preserved; integrate it explicitly before installing.")
    arguments = ' "$1"' if mode == "message" else ""
    scripts[path] = (
        "#!/bin/sh\n" + marker + "\nset -eu\n"
        'git_dir="$(git rev-parse --git-common-dir)"\n'
        'exec python3 "$git_dir/hooks/privacy_guard.py" ' + mode + arguments + "\n"
    )
hooks.mkdir(parents=True, exist_ok=True)
for path, content in scripts.items():
    path.write_text(content)
    path.chmod(0o755)
print("Installed repository pre-commit, commit-msg and pre-push checks.")
print("core.hooksPath was preserved. A custom hook directory must forward to repository hooks.")
