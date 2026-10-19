# Git workspace implementation plan

## Contract

Approved experience: Finder directory → repository commit graph → select commits → preview and execute squash or revert. Rebase/reordering and reset are advanced operations. Keep normal Git commit/pull/push/branch management out of this feature. Preserve the existing Finder menu groups, app opening, macOS 14 minimum and Chinese/Japanese/Korean/English localization.

Sources: existing MenuBuilder/CommandRunner/FinderSync dispatch and App windows; Gitify v1.16.1 GitKit library, graph model and CLI operations; user-confirmed scope in this conversation. Implementation began on the existing master branch. Git operation tests use disposable repositories. No project branch/worktree creation or automatic release.

License constraint: preserve SuperMenu GPL v2. GitKit v1.16.1 is MIT; retain its entire license and copyright in source and packaged app. Its target has no package dependencies. Gitify's app-only Sparkle dependency must not be linked or bundled. Inspect resolved versions and executable linkage; do not introduce Apache-2.0 packages as substitutes. License compatibility is an engineering review of declared licenses, not a guarantee about third-party provenance.

## Responsibilities and file budget

- Package.swift/Package.resolved and scripts/build.sh: pinned GitKit integration into a static host library; Finder extension remains independent.
- Sources/SuperMenuGit (3 files): repository snapshots, operation plans, Git execution, rebase todo generation and recovery.
- Tests/SuperMenuGitTests (2 files): real temporary repositories for content/history/conflicts/worktrees/graph and stale-preview checks.
- App (6 Swift files, plus Info.plist): graph/detail window, preview editor, operation/conflict state; URL entry and license viewer.
- Core Commands/MenuBuilder, Host CommandRunner/MenuIcons, App Info.plist: one Finder entry and URL handoff only.
- Four localization files, third-party notices/license, this log: translated interaction and distributable attribution.
- Four READMEs and two site files: feature instructions, build requirements and organization URLs.
- Two privacy scripts, one synthetic test file, privacy documentation and cache ignore rules: repository-local prevention of accidental identity/data publication. Tests must contain no real personal or machine identifiers.

## Execution and acceptance

- [x] Pin GitKit, verify actual dependency licenses; build only its library target.
- [x] Write behavior checks against real temporary repositories before operation implementation. Baseline has no Git workspace or history actions (MenuBuilder and Package.swift inspected).
- [x] Implement repository discovery from nested paths/worktrees, all-ref topology and paging, commit file/diff inspection.
- [x] Implement previews bound to HEAD/branch/index/worktree state. Reject stale previews, overlapping operations and unresolved states. Display local-known remote reachability, without fetching or pushing.
- [x] Implement squash of a contiguous linear segment (including root); replay descendants without changing final tree. Rebase editor reorders/combines/renames a linear segment. Explain unsupported merge selections instead of flattening merges.
- [x] Implement revert in explicit newest-first order, reset modes with exact effects, and persistent Git-native conflict continue/abort controls. Require explicit merge-parent handling or explain unsupported merge revert.
- [x] Integrate main-app window and Finder handoff; keep Git subprocesses outside FinderSync. Four-language strings and native adaptive icons.
- [x] Run repository tests, core/host regression checks, app build, license/linkage inspection and available UI checks.
- [x] Owner review 1: all requirements against full diff, deletions and untracked files. Owner review 2: correctness, history safety, regression and packaging.

## Review focus

Empty repositories, nested worktrees, Unicode/quotes in paths; merges and root commits; selected commits outside HEAD ancestry; external changes after preview; conflict interruption/relaunch and cancellation. No claim of Finder GUI acceptance without an observed Finder click. No claim of licensing zero risk.

## Current validation and delivery state

- Git/core test suite: 43 passing tests. Host menu checks and native app/extension build passed.
- Native app exercised against a disposable repository: branch/merge graph, file diff, squash preview/execution, revert preview/execution, and bundled licenses.
- Exact upstream MIT and project GPL texts are packaged. App and extension linkage and bundle contents exclude Sparkle.
- Finder URL/menu dispatch is covered in code checks; a real Finder extension click remains unverified.
- Privacy checks: 9 synthetic integration tests passed. Repository-local pre-commit, commit-msg and pre-push hooks, without replacing global hooks. Synthetic tests cover identity overrides, staged data, old ancestors, annotated tags, deleted historical secrets, redacted diagnostics and installer preservation.
- Public project links and origin now target `openmacapp/supermenu`; Pages links target `openmacapp.github.io/supermenu/`.
- Delivery scope: publish the source repository and existing Pages site at the organization URLs above. Remote availability and workflow status must be verified after publishing; no signed or notarized binary release is included.
- Repository metadata cleanup preserved historical code trees and pending files. Private metadata is not copied into source or tests.


## Owner review

Requirements pass: reviewed the full tracked diff and new files, including dependency notices, translations, history operations, private-data handling and project links. No deleted source files or parallel implementation tasks remain. Finder GUI activation and remote deployment remain explicitly unverified.

Correctness pass: checked replay ordering, root/merge handling, snapshot revalidation, mutation serialization, conflict recovery, installed-hook forwarding, staged-versus-working-copy checks and historical scans. The installed privacy checker survives an older working tree; organization links are consistent in the app, website and all READMEs.
