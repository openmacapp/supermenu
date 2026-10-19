#!/usr/bin/env python3
# SuperMenu privacy guard implementation
"""Check commit identities and accidental private data without printing matches."""

import argparse
from pathlib import Path
import re
import subprocess
import sys


class PrivacyError(Exception):
    pass


NOREPLY = re.compile(rb"[^@\s<>]+@users\.noreply\.github\.com", re.I)
IDENTITY = re.compile(rb"(.*?) <([^<>]+)> \d+ [+-]\d{4}")
HOME_PATH = re.compile(rb"/(?:Users|home)/([^/\s\"'<>;)]+)")
PUBLIC_EXAMPLE_USERS = {b"example", b"user", b"username"}
PATTERNS = {
    "machine-specific temporary path": re.compile(
        rb"/(?:private/)?var/folders/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+"
    ),
    "private key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "access token": re.compile(
        rb"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
        rb"|AKIA[A-Z0-9]{16}|sk-[A-Za-z0-9_-]{24,}|xox[baprs]-[A-Za-z0-9-]{20,})"
    ),
    "credential in URL": re.compile(rb"https?://[^\s/:]+:[^\s/@]+@"),
}


def git(*arguments):
    result = subprocess.run(["git", *arguments], capture_output=True)
    if result.returncode:
        raise PrivacyError("Git inspection failed; nothing was approved.")
    return result.stdout


def check_identity(value, location, allow_github_bot=False):
    match = IDENTITY.fullmatch(value.strip())
    if match:
        name, email = match.groups()
        if NOREPLY.fullmatch(email):
            return
        if allow_github_bot and name == b"GitHub" and email == b"noreply@github.com":
            return
    raise PrivacyError(location + ": use a GitHub users.noreply.github.com identity.")


def check_content(data, location):
    for match in HOME_PATH.finditer(data):
        if match.group(1) not in PUBLIC_EXAMPLE_USERS:
            raise PrivacyError(location + ": machine-specific home path detected.")
    for label, pattern in PATTERNS.items():
        if pattern.search(data):
            raise PrivacyError(location + ": " + label + " detected.")


def check_staged():
    for role in ("AUTHOR", "COMMITTER"):
        check_identity(git("var", "GIT_" + role + "_IDENT"), role.lower())
    # Inspect index blobs, including newly added files, not their working copies.
    seen = set()
    for entry in git("ls-files", "--stage", "-z").split(b"\0"):
        if not entry:
            continue
        metadata, path = entry.split(b"\t", 1)
        mode, oid, stage = metadata.split()
        if stage != b"0":
            raise PrivacyError("Resolve index conflicts before committing.")
        if mode == b"160000" or oid in seen:  # Submodule content belongs to its own repo.
            continue
        seen.add(oid)
        check_content(git("cat-file", "blob", oid.decode()), "staged file " + repr(path.decode(errors="replace")))


def check_history(revisions):
    # Resolve first, so command-line input cannot become rev-list options.
    roots = [git("rev-parse", "--verify", "--end-of-options", ref).decode().strip() for ref in revisions]
    if not roots:
        return
    objects = git("rev-list", "--objects", *roots).splitlines()
    seen = set()
    for entry in objects:
        oid = entry.split(b" ", 1)[0].decode()
        if oid in seen:
            continue
        seen.add(oid)
        kind = git("cat-file", "-t", oid).strip()
        if kind not in (b"blob", b"commit", b"tag"):
            continue
        data = git("cat-file", kind.decode(), oid)
        location = kind.decode() + " " + oid[:10]
        if kind in (b"commit", b"tag"):
            headers, message = data.split(b"\n\n", 1)
            for line in headers.splitlines():
                if line.startswith((b"author ", b"committer ", b"tagger ")):
                    role, identity = line.split(b" ", 1)
                    check_identity(identity, location + " " + role.decode(), allow_github_bot=True)
            check_content(message, location + " message")
        else:
            check_content(data, location)


def check_push():
    revisions = []
    for line in sys.stdin:
        fields = line.split()
        if len(fields) != 4:
            raise PrivacyError("Unexpected pre-push input; nothing was approved.")
        oid = fields[1]
        if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", oid):
            raise PrivacyError("Invalid pre-push object ID.")
        if set(oid) != {"0"}:  # Deleting a ref sends no objects.
            revisions.append(oid)
    # Check every ancestor, even for a new remote or a force push.
    check_history(revisions)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("staged", "message", "history", "pre-push"))
    parser.add_argument("arguments", nargs="*")
    args = parser.parse_args()
    try:
        if args.mode == "staged":
            check_staged()
        elif args.mode == "message":
            if len(args.arguments) != 1:
                raise PrivacyError("Expected a commit message file.")
            check_content(Path(args.arguments[0]).read_bytes(), "commit message")
        elif args.mode == "history":
            check_history(args.arguments or ["HEAD"])
        else:
            check_push()
    except (PrivacyError, OSError) as error:
        # Never print the matched email, token, private path, or Git stderr.
        message = str(error) if isinstance(error, PrivacyError) else "Unable to read required input."
        print("Privacy check blocked: " + message, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
