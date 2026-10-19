# Third-party software

SuperMenu is distributed under the GNU GPL version 2; see LICENSE. Third-party
components retain their own copyright notices and licenses below.

## GitKit (Gitify v1.16.1)

- Source: https://github.com/craigharman/gitify/tree/v1.16.1/Sources/GitKit
- Revision: dbcbba1c019b5d46895cae99fea6c2c0a0d9944c
- Copyright (c) 2026 Craig Harman
- License: MIT; full text: ThirdPartyLicenses/Gitify-MIT.txt
- Use: Git command execution, data parsing, and commit graph layout.
- Source is unmodified. SuperMenu history planning and UI are separate modules.

The GitKit target depends only on Apple system frameworks. SwiftPM resolves
Sparkle 2.10.0 because Gitify's package also defines an application target, but
SuperMenu builds and links only GitKit. Sparkle is not linked or included in the
SuperMenu application or Finder extension. Its resolved source and bundled
component license texts can be inspected at:
https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE

The app's About window provides the full bundled license texts. Distribution
must preserve these notices and provide corresponding SuperMenu and dependency
source, including build scripts, as required by GPL v2. A binary release must
include its matching source archive/dependency revisions; a link to a moving
branch alone does not identify the corresponding source.

Git commands use the locally installed Git executable. SuperMenu does not bundle
Git, Gitify's app, GoLand, GitLens, their artwork, or their source code. GoLand and
GitLens are interaction references only.
