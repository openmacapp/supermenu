# Commit privacy checks

Before contributing, configure this repository with the GitHub private email
shown in your GitHub email settings, then install the checks:

```sh
python3 scripts/install-privacy-hooks.py
git hook run pre-commit
```

The installer writes only repository-local hooks. It does not change global Git
configuration, `core.hooksPath`, or overwrite unrelated existing hooks. If you
use a custom hook directory, it must forward to these repository hooks; verify
this before committing. Hooks are not activated automatically by cloning a repo.
The installed checker is copied into the Git hooks directory, so checks survive
checking out or replaying an older tree without the script. Rerun the installer
after updating the checker source.

- `pre-commit` checks the actual author/committer identity and index blobs.
- `commit-msg` checks the final commit message.
- `pre-push` checks all ancestors and blobs reachable from the refs being pushed,
  including when publishing to a new remote or force-pushing.

Human identities must use `users.noreply.github.com`. GitHub's own public bot
identity is allowed in existing history. Checks reject machine-specific home and
temporary paths, private-key markers, recognized token formats and credentials
embedded in URLs. Public example home paths are allowed. Diagnostics identify
the file or object, without echoing matched private data.

Run checks manually and exercise rejection cases with synthetic data:

```sh
python3 scripts/privacy_guard.py staged
python3 scripts/privacy_guard.py history HEAD
python3 -m unittest discover -s Tests/privacy -v
```

Tests use only invented identities and temporary local repositories. They never
contact an external remote or contain a contributor's real environment details.

These checks cover the configured patterns, not every possible secret. Hooks
can be bypassed or uninstalled, so reviewers still need to inspect changes and
the actual commit identities before publishing. Remote checks or protection
rules must be configured separately when a hosted repository is created.
