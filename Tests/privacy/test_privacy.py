"""Real Git hook checks using invented identities and disposable repositories."""

from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2]
PUBLIC_EMAIL = "12345+sample@users.noreply.github.com"
PRIVATE_EMAIL = "sample@example.invalid"


class PrivacyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="privacy-fixture-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Sample Contributor")
        self.git("config", "user.email", PUBLIC_EMAIL)
        self.git("config", "commit.gpgsign", "false")
        (self.root / "scripts").mkdir()
        for name in ("privacy_guard.py", "install-privacy-hooks.py"):
            shutil.copyfile(SOURCE / "scripts" / name, self.root / "scripts" / name)
        self.run_command(sys.executable, "scripts/install-privacy-hooks.py")
        (self.root / "file.txt").write_text("public content\n")
        self.git("add", ".")

    def run_command(self, *args, success=True, env=None):
        result = subprocess.run(args, cwd=self.root, env=env or self.env, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, "Expected privacy check to reject operation")
        return result

    def git(self, *args, **kwargs):
        return self.run_command("git", *args, **kwargs)

    def test_public_identity_commits_and_pushes(self):
        self.git("commit", "-m", "Public fixture")
        remote = Path(self.temp.name) / "remote.git"
        self.git("init", "--bare", str(remote))
        self.git("push", str(remote), "HEAD:refs/heads/main")

    def test_private_identity_and_author_override_are_blocked(self):
        self.git("config", "user.email", PRIVATE_EMAIL)
        result = self.git("commit", "-m", "Rejected fixture", success=False)
        self.assertNotIn(PRIVATE_EMAIL, result.stderr)
        self.git("config", "user.email", PUBLIC_EMAIL)
        self.git("commit", "--author", "Sample Contributor <" + PRIVATE_EMAIL + ">", "-m", "Rejected override", success=False)

    def test_index_content_is_checked_even_if_working_copy_is_clean(self):
        private_path = "/".join(("", "Users", "invented-account", "private.txt"))
        (self.root / "file.txt").write_text(private_path)
        self.git("add", "file.txt")
        (self.root / "file.txt").write_text("public working copy")
        result = self.git("commit", "-m", "Rejected staged fixture", success=False)
        self.assertNotIn(private_path, result.stderr)

    def test_token_and_commit_message_are_blocked_without_echo(self):
        token = "ghp_" + "x" * 40
        (self.root / "file.txt").write_text(token)
        self.git("add", "file.txt")
        result = self.git("commit", "-m", "Rejected token fixture", success=False)
        self.assertNotIn(token, result.stderr)
        (self.root / "file.txt").write_text("public")
        self.git("add", "file.txt")
        result = self.git("commit", "-m", token, success=False)
        self.assertNotIn(token, result.stderr)

    def test_push_rejects_bad_ancestor_even_after_good_commit(self):
        self.git("config", "user.email", PRIVATE_EMAIL)
        # Simulate a commit created before hooks were installed.
        self.git("-c", "core.hooksPath=" + str(Path(self.temp.name) / "empty-hooks"), "commit", "-m", "Old private fixture")
        self.git("config", "user.email", PUBLIC_EMAIL)
        (self.root / "file.txt").write_text("next public content")
        self.git("add", "file.txt")
        self.git("commit", "-m", "Public descendant")
        remote = Path(self.temp.name) / "remote.git"
        self.git("init", "--bare", str(remote))
        result = self.git("push", str(remote), "HEAD:refs/heads/main", success=False)
        self.assertNotIn(PRIVATE_EMAIL, result.stderr)
        self.assertEqual(self.git("--git-dir=" + str(remote), "show-ref", success=False).stdout, "")

    def test_install_preserves_existing_hooks(self):
        hook = self.root / ".git/hooks/pre-commit"
        original = "#!/bin/sh\nexit 0\n"
        hook.write_text(original)
        self.run_command(sys.executable, "scripts/install-privacy-hooks.py", success=False)
        self.assertEqual(hook.read_text(), original)

    def test_installed_guard_survives_working_copy_removal(self):
        self.git("commit", "-m", "Public fixture")
        self.git("rm", "scripts/privacy_guard.py")
        self.git("commit", "-m", "Simulate older tree without guard source")
        self.git("config", "user.email", PRIVATE_EMAIL)
        self.git("commit", "--allow-empty", "-m", "Still protected", success=False)

    def test_push_rejects_private_annotated_tag(self):
        self.git("commit", "-m", "Public fixture")
        self.git("-c", "user.email=" + PRIVATE_EMAIL, "tag", "-a", "v1", "-m", "Private tag fixture")
        remote = Path(self.temp.name) / "remote.git"
        self.git("init", "--bare", str(remote))
        self.git("push", str(remote), "refs/tags/v1", success=False)

    def test_history_rejects_private_file_deleted_by_later_commit(self):
        token = "ghp_" + "y" * 40
        (self.root / "private.txt").write_text(token)
        self.git("add", ".")
        self.git("-c", "core.hooksPath=" + str(Path(self.temp.name) / "empty-hooks"), "commit", "-m", "Old fixture")
        self.git("rm", "private.txt")
        self.git("commit", "-m", "Remove old fixture")
        result = self.run_command(sys.executable, "scripts/privacy_guard.py", "history", "HEAD", success=False)
        self.assertNotIn(token, result.stderr)


if __name__ == "__main__":
    unittest.main()
