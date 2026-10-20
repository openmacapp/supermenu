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

## Compact history and diff correction contract

User evidence: the history screenshot has 60-point, three-line rows and an empty half-window; file navigation and diff highlighting are insufficient. Code evidence: history loads one file, but operation previews concatenate unrestricted patches and the runner buffers all output.

Deliver compact one-line history columns, default HEAD selection, a resizable lower inspector, searchable changed-file navigation shared by history and operation previews, one cancellable and bounded file patch at a time, adaptive addition/deletion/hunk highlighting and old/new line numbers. Preserve multi-selection, contextual operations, four languages, repository discovery, safety checks and Git operation semantics. Do not add commit/push/branch management or dependencies. Preview limits must be visible, never presented as complete content.

File budget: existing workspace view/model and plan view; one shared App diff browser and its existing About license-text caller; existing GitWorkspace/GitPlan plus one focused Git diff reader/model; one focused temporary-repository test file; four localization files; this log. Existing tests verify mutation behavior; new checks cover file isolation, literal paths/renames, root/merge comparisons, binary output, bounded large output and cancellation. Native UI verification must cover row density, initial selection, file search/switching, highlighting and operation preview. No private repository data in fixtures. Work stays on the existing branch.

### Correction validation and owner review

- Requirement review: compact 26-point history rows replace 60-point rows; initial HEAD selection opens the lower inspector. History and operation confirmation use the same searchable file browser. Multi-commit revert offers an explicit commit selector. Full commit messages and SHA remain available in the details popover. All added labels exist in four languages.
- Correctness review: checked the full tracked diff and all three new files, including removed eager patch loading. Immutable comparisons preserve squash/reset/revert directions; merge inspection uses the first parent. File reads use literal paths, include rename endpoints, stop at 512 KiB or 10,000 lines, and skip text diff when either input blob exceeds 8 MiB. Cancellation terminates patch processes and cancelled tasks cannot publish content. Mutations and snapshot guards remain unchanged; no new dependency, branch or parallel task.
- Validation: 49 Swift tests passed, including six focused diff tests; native app and Finder extension build passed. Changed-file privacy scan and whitespace checks passed. Synthetic fixtures cover 250 files, root and merge comparisons, reverse patches, rename paths containing tabs/newlines, binary data, long lines, large inputs and cancellation.
- Native UI observed on the installed intermediate build: initial selection, compact rows, visible addition/deletion/hunk colors and old/new line numbers; 123-file search, keyboard file switching, binary and truncation messages; squash file navigation and per-commit revert previews. No operation was executed in a user repository.
- Final build copied to the installed app with signature and byte equality checks; previous bundle retained locally. Native window control became unavailable before the final restart. The final input-size guard is covered by tests; final date formatting, details popover and scroll-origin refinements are built but not yet rechecked in the restarted installed app. Changes are local and have not been committed or pushed.

## Menu bar responsibility correction

User screenshot shows Finder copy/open/create/send/tool groups in the status menu without a visible target. Existing MenuBarMenu synchronously queries FinderBridge and renders MenuNodeList; the only FinderBridge caller is this menu. Replace it with explicit Open Git Repository, Settings, About and Quit entries. Finder extension actions and system services remain unchanged; reuse the existing window/repository entry points. Remove the unused bridge and automation permission descriptions. Update all four languages and existing README/site guidance. Preserve pending Git inspector changes and the current branch.

File budget: SuperMenuApp.swift, removal of FinderBridge.swift, App Info.plist and its four localized permission descriptions, four core localization files, four READMEs, site/index.html and site/site.js, this log. Validate native build, localization/core regressions, Finder host checks, removed-reference searches and actual menu when native UI control is available. No new Git operations, dependencies or website deployment.


### Menu bar validation and owner review

- Requirements pass: reviewed the complete accumulated diff, including the deleted Finder bridge and three pending Git inspector files. The tray now contains repository selection, settings, About and Quit. Finder context-menu construction and system services remain in place. Four-language guidance and existing documentation match this boundary.
- Correctness pass: confirmed the deleted bridge has no remaining callers, removed automation permission descriptions and obsolete error keys, and checked menu actions against the existing window/repository handlers. Previous Git preview cancellation, comparison direction and bounded rendering changes remain intact. No parallel work is outstanding.
- Native app/extension build, 32 core tests, Finder host menu checks and website JavaScript syntax check passed. The installed bundle passed signature and binary equality checks. The old process was quit and the new app launched successfully; the updated settings explanation is visible. This resolves the earlier restart blocker. Direct expansion of the status-menu popup remains unverified because the UI tool exposes the app window but not that menu extra; the final Git visual refinements also remain without a fresh UI check.
- Changes remain local; no commit, push or website publication was performed.


## Branch and diff robustness validation contract

Request: verify branch-related behavior, directory/file browsing performance and abnormal files entering diff. Facts: the app has all-ref history and current-branch history operations, but no branch-management UI and no collapsible directory tree; the inspector is a searchable changed-file list. Previous acceptance must not imply those missing capabilities exist. The diff reader caps patch output and large input blobs, but file-list/metadata reads use the buffered runner and binary detection happens after patch generation.

Validate only with synthetic temporary repositories: divergent local/remote refs, detached HEAD and external branch changes, nested paths and thousands of files, read-only history despite working-tree changes, binary/forced-text attributes, symbolic links, gitlinks, missing objects and rapid cancellation. Preserve history mutation semantics, four languages, existing local edits and current project branch. Do not add branch CRUD or a new tree UI under a testing request; report these gaps explicitly. No commit/push/deployment or real-project history mutations.

File budget: existing GitDiff implementation, one focused bounded Git reader if needed for cancellation/resource limits; existing diff and safety tests plus one performance/robustness test file; existing preview view and four locales only for explicit omitted-content/error states; this log. Measure real file-list/patch latency without hardware-dependent pass thresholds. Run full Swift tests and native build for any fixes. Owner reviews cover the accumulated diff including untracked files and deletion. Performance numbers are local data-path measurements unless actual GUI rendering is observed separately.


### Robustness results and remaining gaps

- Reproduced before fixing: a binary blob forced through text diff by attributes reached the text renderer; local `diff.ignoreSubmodules=all` hid a changed gitlink. Both tests failed on the earlier implementation and pass after the correction.
- GitDiff.swift now samples historical blobs before generating a patch, rejects control bytes in returned text, reports unsupported UTF-8 explicitly, and pins short gitlink display without following submodule contents. BoundedGitRead.swift centralizes cancellable file-list, metadata, blob-sample and patch reads, with a 10-second per-process deadline. File-list output has an 8 MiB cap with an explicit error rather than a partial list. Existing 8 MiB input and 512 KiB / 10,000-line patch limits remain.
- Tests: all 58 Swift tests passed. New real-repository checks cover divergent branch selection, unchanged other refs after squash, same-commit external branch switches, detached HEAD, symbolic links/untracked content, missing objects, invalid encoding, external diff/textconv suppression, deadlines and 20 cancelled reads. Existing tests continue to cover conflict recovery, reset modes, merges, root commits, literal/renamed paths, binary data and oversized files. No project branch changes or real-project history mutations occurred.
- Performance fixture: 5,000 files across 100 nested directories, followed by 40 individual patch reads. Latest full-suite run: file list 24.7 ms, median patch 104.5 ms, P95 179.4 ms, maximum 202.4 ms. An earlier focused run measured 25.4 / 112.5 / 247.6 / 290.8 ms respectively. These are local debug-build data-path timings, not frame-time or cross-machine guarantees.
- Native app and extension build passed; installed bundle signature and binary equality verified, then app restarted. Actual installed UI loaded 5,004 changed files; directory-path filtering, keyboard switching, binary and oversized-input notices, long-patch limit message, hunk/addition highlighting and return to a small file were observed. Five complete large/small switching cycles remained responsive. RSS samples were 204.2 MiB before a long patch, 227.0 MiB while showing it, 228.5 MiB after returning, and 236.4 MiB after five cycles. No direct Git child remained after inspection. These samples do not establish leak freedom or long-duration stability. Further UI cycling was interrupted by a ScreenCaptureKit capture failure; it is not counted as completed.
- Requirement review: checked the complete accumulated tracked diff, the deleted bridge and all five new files against the contracts. Branch CRUD and a collapsible directory tree remain unimplemented; the delivered inspector is a searchable list. File budget additions are the bounded reader for lifecycle limits and the robustness test file for real-repository behavior/performance; four locale updates explain failure states. Prior menu-bar and Git UI changes remain intact.
- Correctness review: checked immutable comparison directions, literal path boundaries, object-only blob inspection, submodule/config behavior, bounded decoding, process termination/reaping, cancellation propagation, UI stale-result checks, translations and documentation/deletions. Mutation code and dependency versions are unchanged in this batch. No parallel work remains. Full-suite/build evidence does not stand in for missing branch/tree features or long-duration UI profiling.
- Changes remain local and installed for validation, without a new commit, push or website publication.


## Finder Git badge cache design (planned, not implemented)

### Contract and evidence

User request: SVN-style Finder file/folder status badges, memory-only Git status caching, bounded memory, LRU eviction and abnormal-state self-check/recovery. No project-directory or `.git` cache writes; no contents, patches, identities or emails in cache fixtures/diagnostics. Preserve existing Finder menus, Git history operations, diff limits, current branch and all pending changes. This batch changes only this existing planning log; it does not implement, commit, install or publish the feature.

Verified baseline: `Extension/FinderSync.swift` registers `/` for menu coverage and has no badge callbacks; no existing host/extension snapshot transport was found. The extension is sandboxed; existing URL handoff opens the host but does not provide status IPC. `BoundedGitRead.swift` provides cancellable, byte-limited reads and a deadline, but the current workspace status read is buffered and must not be reused unchanged for background badges. Git status computation belongs to the host; Finder callbacks only read a small local snapshot. Apple documents multiple extension instances, non-strict NSCache limits and FSEvents dropped-event recovery (sources below).

Choose a host-owned, explicitly costed LRU with bounded per-extension projections. Full repository copies in every extension multiply memory; disk snapshots violate the agreed memory-only scope. The IPC mechanism remains a feasibility gate: verify an authenticated, bounded connection under the actual signing/sandbox setup before implementing the full cache. Do not claim that XPC is already configured or introduce a disk fallback silently. The host must be running for fresh badges; disconnect means unknown status, not a host-launch loop.

### Initial budgets and accounting

These are proposed admission/accounting limits, not measured RSS guarantees. Actual allocation overhead, framework baselines, IPC copies and Git child-process memory must be profiled separately.

| Owner/resource | Initial limit | On exhaustion |
| --- | --- | --- |
| Host retained snapshots, indexes, LRU nodes and directory aggregates | 24 MiB globally; 4 MiB per repository; 16 repositories | Evict least recently used complete repository snapshots before admission |
| Host transient scan/parser and IPC staging allocations | 8 MiB combined; included alongside retained usage in a 32 MiB accounting ceiling | Cancel/defer work before allocating beyond the reservation |
| Status scan input | 2 MiB output and 20,000 records per scan; count path and ancestor expansion costs separately | Discard the incomplete snapshot, mark repository unavailable/over-budget |
| Extension projection | 1 MiB and 2,000 path entries per instance; combined live projection leases 8 MiB across clients | Evict local entries; refuse/defer additional leases, remove obsolete badges |
| IPC batches | 128 KiB per message, one unacknowledged batch per client; staging charged above | Backpressure/coalesce; never queue full successive snapshots |
| Work scheduling | One badge status scan globally, one pending refresh per retained repository | Coalesce invalidations; cancel obsolete work |
| Repository discovery | 256 bounded negative entries with 30-second TTL, charged to host budget | LRU eviction; invalidate on relevant directory changes |

All paths, ancestor nodes, dictionary/list capacity, strings/data backing storage, visible-item registries, client leases, watcher metadata and retry state count toward admission. A serialized payload length alone is not a Swift heap size estimate. Use conservative measured costs and entry/byte dual limits, reserve replacement snapshots before construction and avoid retaining old/new copies outside the budget. Scope keys to canonical worktree root plus resolved Git directory; linked worktrees sharing a common Git directory must not share worktree status. Reject or bypass oversized/undecodable records rather than publish a partial healthy result.

Keep only changed/untracked states and bounded ancestor aggregates; a missing entry does not prove clean. Initial UX leaves clean/unknown items unbadged. If a clean checkmark is later requested, require independently verified tracked membership and a complete fresh snapshot. Ignored and non-repository paths remain unbadged. Nested repositories and submodules are separate boundaries; do not recurse through symlinks or submodule contents. Only status metadata enters the application for badges, so binary/large files do not enter the diff pipeline. Git itself may inspect working files to compute status.

### LRU and lifecycle

- Repository granularity preserves coherent directory aggregates. Extension projections use per-path LRU. User-visible requests advance recency; background refresh/retries do not keep inactive entries hot. Visible repositories receive scheduling preference but are not pinned above limits.
- Expire inactive repository snapshots/watchers after five minutes. Expiration, eviction, disabling badges, root removal and client disconnect release tasks, watches and leases; send bounded invalidation messages to clear already-displayed affected badges. Extension lease expiry also clears badges if the host disappears before notifying it.
- Every snapshot carries host-session ID, repository generation, completion status and a 30-second freshness lease. New invalidation immediately expires the affected projection; old asynchronous replies cannot replace a newer generation or host session. Revalidate repository identity and HEAD/index metadata before and after scans; filesystem events during a scan cause a retry. This limits staleness but cannot make a live filesystem scan atomic.
- Refresh on filesystem/Git metadata changes and completed app Git operations. Debounce normal bursts by 300 ms with a two-second maximum scheduling delay, subject to scan/CPU backpressure. Watch linked worktree metadata and the common Git directory, not just `<root>/.git` as a directory. No recursive disk-wide watcher or scan just because menu coverage registers `/`.
- Scan deadline starts at ten seconds. Preserve bounded-reader cancellation, reap subprocesses and verify termination under blocked/slow-process tests; strengthen termination if those tests expose an unbounded wait. Background scans must yield to foreground Git mutations. Empty stdout is a valid no-changes result only after successful exit and complete repository validation; cancellation, timeout and parse failure cannot be interpreted as clean status.

### Self-check and recovery

Use explicit states: loading, fresh, stale, backingOff and unavailable (with reason). Only complete fresh snapshots publish status badges; every other state removes expired badges. No filesystem repair, Git reset, automatic fetch or repository writes are part of recovery.

- On active use, perform a lightweight health check at most every 30 seconds: lease age, host connection, generation, root identity, permissions, watcher health and in-flight deadline. Idle repositories have no periodic scan. Lease expiry invalidates locally even without host messages.
- On event overflow/dropped events, watcher restart, sleep/wake or volume replacement, discard affected generations and schedule a bounded full repository-status refresh. Coalesce repeated errors into one dirty marker; never accumulate an event backlog. If the bounded scan cannot complete, remain unavailable.
- Check local cache invariants after mutations: accounted usage within limits, LRU and lookup entries agree, no duplicate worktree key, no orphaned lease/task/watcher, aggregate generation matches its source. On violation clear only the affected cache partition and rebuild lazily. Diagnostic builds can run exhaustive checks; release checks must not repeatedly walk every file on a timer.
- Retry transient scan/IPC failures with jittered 1, 2, 4 and 8-second delays after the first four failures. After the fifth consecutive failure pause automatic scans for five minutes; foreground explicit refresh, meaningful repository change or reconnection permits one coalesced probe, still rate-limited. Stable size/permission/unsupported-path failures wait for relevant changes or explicit retry. No repeated dialogs or stderr/path dumps.
- Memory pressure warning drops idle snapshots and lowers admission limits by half; critical pressure cancels background scans and clears cached projections/snapshots, invalidating badges. Recover gradually after pressure subsides; do not reload all evicted repositories at once. Bound counters and error samples; expose counts/bytes/latency/error categories without raw paths, command output or identities.

### Verification and implementation order

1. Prove memory-only host/extension transport and disconnect/expiry behavior with two extension clients under the actual sandbox/signature. If unavailable, revise the transport design before product implementation. Use synthetic locations/identities only.
2. Implement the independently testable cache budget/LRU and generation state machine, then the bounded Git status reader and folder aggregation; connect the actual Finder callback last. Reuse the existing bounded reader where appropriate, without changing mutation semantics or bypassing diff protections.
3. Deterministic tests: exact boundary and oversized-entry admission; LRU reads versus background refresh; ancestor fanout and long paths; replacement reservations; 17+ repositories; 2,001+ visible entries; multiple-client lease exhaustion; slow consumer and bounded IPC; stale/out-of-order replies; disconnect/restart; memory pressure; event loss; retry limits; cancellation and resource release. Prove both bounded costs and removal of stale badges, not merely successful reads.
4. Synthetic Git cases: nested folders, linked worktrees, detached/unborn HEAD, rename/delete, ignored/untracked paths, conflict, nested repositories/submodules, symlink, invalid path encoding, denied access, deleted root and changing index/HEAD during scans. Compare directory summaries with complete Git results only on successful bounded scans. Inject oversized output and confirm no false clean/partial snapshot.
5. Native profiling: 1k/10k/100k-path fixtures, many changed paths and long/deep names; more repositories than capacity; repeated Finder navigation and Open/Save extension instances; external branch switch, sleep/wake, host kill/restart and unavailable volume. Measure host plus each extension incremental RSS, Git child peak memory, retained allocation growth, CPU, lookup P95, refresh time and live task/watcher counts. Initial goals: cached lookup P95 under 2 ms; after warmup, 100 navigation cycles and a 30-minute session without monotonically growing retained resources. These are future acceptance targets, not test results.
6. Accounted host data must remain within 32 MiB and each extension projection within 1 MiB at all times. RSS cannot be promised to equal those limits: measure extra heap/framework/process overhead against the same build without badges. Repeated growth or large unexplained overhead blocks acceptance and triggers lower limits or a representation change. Large repositories exceeding limits degrade to no badge with a non-modal diagnostic reason.

Implementation file scope (not changes in this planning batch): focused status/cache types under SuperMenuGit and their synthetic tests; host coordinator/transport and Finder badge adapter; shared bounded message definitions only if the transport proof requires them; existing build/entitlement files only as required by that proof; four localization files for observable status/errors and this log. Establish an exact file budget after the transport proof, before code writes. Preserve current menu-only root coverage and existing capabilities throughout.

### Design review and evidence limits

Requirements review: memory-only privacy boundary, explicit retained/transient/multi-process budgets, weighted LRU, stale badge removal and abnormal-state recovery are represented above. No new runtime code or dependencies, user-repository mutations, commits or deployments are included. Existing pending work is unchanged.

Correctness review: budgets include replacement/IPC costs and derived directory entries; clean status is not inferred from missing entries; extension multiplicity, linked worktrees, stale generations, failed scans and dropped events have explicit behavior. These numbers are initial policy choices. Sandbox IPC feasibility, practical heap costs, Git child memory, filesystem race windows and actual Finder badge removal remain unverified and can overturn the design; tests and profiling are prerequisites to any completion claim.

Sources:
- Apple Finder Sync guide (multiple instances and lightweight extensions): https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html
- Apple NSCache totalCostLimit (non-strict limits and unspecified eviction order): https://developer.apple.com/documentation/foundation/nscache/totalcostlimit
- Apple FSEvents dropped-event recovery: https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html


## Finder badge execution plan

User approved execution of the cache design. Execute inline on the current branch; no agents, commit/push or branch/worktree changes. Existing dirty changes are preserved. Use failing behavioral tests, then implement and verify each unit. This section is the implementation plan and ledger; it supersedes speculative transport details above.

Transport proof: signed sandboxed Unix socket clients were denied, even with network entitlements. Signed sandboxed Mach message clients succeeded twice using only a named Mach lookup exception. Choose bounded Mach request/reply with kernel audit-trailer UID validation in both directions; no disk endpoint, network entitlement, shared secret or status file. Formal transport tests must cover two clients, unauthorized/malformed replies, payload bounds, timeout and restart before integration. Existing app ad-hoc signing remains unchanged.

Exact file budget and order:
1. `Sources/SuperMenuCore/BadgeTransport.swift`, `BadgeProtocol.swift`, `Tests/SuperMenuCoreTests/BadgeTransportTests.swift`: bounded memory-only transport and messages, signed sandbox probe. Modify only the extension's named Mach lookup entitlement for connectivity.
2. `Sources/SuperMenuCore/BadgeCache.swift`, `Tests/SuperMenuCoreTests/BadgeCacheTests.swift`: deterministic cost/entry LRU, leases and retry state; no NSCache soft-limit dependency.
3. `Sources/SuperMenuGit/GitBadgeStatus.swift`, `Tests/SuperMenuGitTests/GitBadgeStatusTests.swift`: cancellable bounded discovery/status parsing and ancestor aggregation. Amend `BoundedGitRead.swift` only if resource/cancellation tests require it.
4. `App/GitBadgeService.swift`, `App/GitBadgeWatcher.swift`, `Extension/FinderBadges.swift`: host scan scheduling, invalidation/watchers, bounded clients and Finder callbacks. Hook `App/SuperMenuApp.swift` and `Extension/FinderSync.swift`; configuration toggle in existing Config/Settings plus four core locales. Add focused service tests via the existing host-test script pattern if needed.
5. Existing build script only if compilation requires it; existing README language files for the capability/host-running requirement; this log for evidence. Run full Swift tests, host checks, native build and privacy checks. Profile synthetic repositories and actual Finder behavior, then owner-review the full diff twice, including earlier pending work and new files.

Acceptance: limits and timeout/eviction must fail closed to absent badges, never false clean; failed Git reads cannot publish partial snapshots; callbacks never run Git or wait for IPC; versions reject stale replies; host disconnect and lease expiry remove displayed badges. Memory/CPU measurements must distinguish accounted data from process RSS. No claims for unperformed UI or duration tests.


### Implemented behavior and acceptance ledger

- Memory ownership: host repository LRU is capped at 23 MiB / 16 entries, directory discovery at 256 KiB / 256 entries, leaving retained metadata headroom within the 24 MiB policy. A parsed repository reserves 128 KiB of its 4 MiB allowance for metadata. Finder projects at most 512 KiB / 2,000 entries and observes at most 64 directories / 64 KiB; remaining headroom is reserved for bounded messages and decoding. Costs are conservative estimates, not measured Swift allocation or RSS guarantees. Git child peak memory remains unprofiled.
- Transport: kernel audit UID validation in both directions, kernel PID client leases, at most eight clients. Application JSON is limited to 24 KiB and 128 paths / 16 KiB of path bytes, below the 128 KiB transport ceiling. Two concurrently signed App Sandbox clients reached the real service implementation. No disk status data, network entitlement, new dependency or license was added.
- Scheduling: one background status task, repository-level coalescing, FSEvents invalidation, 30-second freshness, five-minute inactive eviction, jittered exponential backoff and five-minute pause after five consecutive failures. App history mutations cancel and await background reads. Warning pressure halves retained admission; critical pressure clears/cancels and waits for a normal event before gradual recovery. Cache invariants are audited every 30 seconds.
- Implementation refinement: request/reply polling uses one in-flight batch per extension, rather than an unsolicited invalidation channel. Normal invalidations are noticed by the next reply, while lease expiry independently clears old badges within 30 seconds if communication is lost. Only changed badge identifiers are sent back to Finder. Git deadlines are per subprocess (10 seconds); discovery and status involve several processes. Blocking filesystem metadata calls on unavailable volumes are not preemptible and stay off the coordinator/main queues.
- Repository identity is rediscovered before scans, with separate canonical worktree roots and resolved Git directories. Filesystem events and metadata fingerprints reject racing reads. macOS path aliases are normalized for discovery/comparison while response keys retain the caller's spelling. This is bounded eventual consistency, not an atomic filesystem snapshot.
- Read termination regression: a synthetic helper ignoring TERM and keeping stdout open made a 50 ms deadline take about 2 seconds. Verified process-group termination plus nonblocking pipe reads corrected it; the regression completed in about 0.24 seconds. Read-only inspection uses this reader; mutation execution remains on its existing path.
- Validation: 75 Swift tests passed, followed by seven cache tests after tightening projection headroom. Service integration covers real status, filesystem changes, disable/re-enable, cached requests, client cap, memory pressure, 18-repository eviction and repeated reset recovery. Native app/extension build, Finder menu host checks, website syntax and working-tree/history privacy checks passed. All fixtures use synthetic identities and disposable repositories.
- Latest full-suite local data-path timings: 1,000 paths about 17 ms, 10,000 about 56 ms, 100,000 rejected as over-budget in about 176 ms; no partial status publishes. Final smaller projection lookup P95 about 0.0005 ms. These are local samples, not Finder rendering latency or universal guarantees.
- Actual Finder validation is not passed: images register and directory observation arrives, but badge request callbacks remain zero. Another enabled Finder extension overlaps the directory; interference is a hypothesis pending an approved temporary toggle. Other apps' settings have not been modified. The native app's settings and service startup are visible; a synthetic direct installed-host probe is separate from Finder rendering acceptance.
- Remaining acceptance gaps: actual badges and their disappearance in Finder/Open-Save instances; final-build 30-minute/100-navigation-cycle allocation profiling, host-plus-extension incremental RSS and Git child peak RSS; physical sleep/wake, unavailable-volume, permission-denial and dropped-event injection. Diagnostics currently expose bytes/failure counts rather than detailed per-repository failure reasons. These gaps prevent a complete end-to-end acceptance claim.

Owner review, requirements pass: read the accumulated tracked diff, removed Finder bridge, all untracked implementation/tests/scripts and the contracts. Existing compact history, bounded per-file diff, menu-bar correction, four-language support and privacy boundary are preserved. Each new file belongs to transport/cache/status, host/watcher/Finder adaptation, or its focused tests; only the timeout regression justified changing the shared read-only reader. No additional agent work, dependency changes, branch changes, commit or push.

Owner review, correctness pass: checked LRU recency/cost replacement, expiry and generation handling, admission eviction during replies, completion after early task eviction, discovery completing after disable, Mach rights cleanup, pressure recovery, subprocess cancellation/reaping, literal immutable diff comparisons, localized settings/config compatibility and removed callers. Corrected the identified lifecycle and path-alias issues. Green tests establish the listed code-path evidence, not the still-open native acceptance gates.


### Runtime follow-up: Finder background menu and path entry

The user reported the missing background context menu during local installation. The extension process had stopped after replacement and did not restart automatically. Re-registering and toggling only the SuperMenu extension restored its process; no other extension setting was changed. Actual Finder background right-click subsequently exposed SuperMenu with copy/open/new/tools and Git history. Invoking Git history opened the current synthetic directory, not a previous selection. No history mutation was performed.

The final installed host also passed a direct synthetic status probe using the alternate macOS path spelling. App and extension signatures and binary equality were verified after the final build/copy. This does not establish badge rendering: requests remain absent while the overlapping extension is active.

For the additional path-entry UX question, the existing app Git menu opens an NSOpenPanel; Command-Shift-G was exercised successfully inside it and opened the native path entry. Finder's own Command-Shift-G was also exercised. Proposed discovery improvements are explicit action labels and a visible repository-switch entry; no custom global shortcut, arbitrary command execution, recent-path persistence, or new navigation feature was added in this batch.

Intermediate-version soak completed: 1,800 seconds / 896 iterations, exit zero, zero read failures, retained test cache 8,120 bytes; sampled standalone test-host RSS 13056–13248 KiB. This binary predates the final pressure, cancellation, projection and alias fixes. It is supporting evidence only, not final-build or actual Finder 30-minute acceptance. The test process exited; no long-running test remains.
