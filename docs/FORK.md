# Fork notes

This is a personal/family fork of [rebornix/Agmente](https://github.com/rebornix/Agmente)
(MIT). It exists to run a private [TestFlight](https://developer.apple.com/testflight/)
build of the app against a self-hosted coding-agent daemon, without waiting on
the App Store listing. It carries **no upstream-mergeable product changes** —
only fork identity (bundle ID, display name), CI, and a TestFlight release lane.

Upstream copyright and the MIT `LICENSE` are kept intact. Nothing here changes
app behavior.

## One client of many

The daemon this app talks to speaks **spec-general ACP** (Agent Client
Protocol). Agmente is just *one* ACP client; other clients (CLIs, editors,
other apps) are equally first-class. So:

- Anything app-specific lives **here, in the fork**.
- The daemon must **never** grow Agmente-specific behavior. If you find
  yourself wanting the server to special-case this client, that's a smell —
  fix it in the fork instead.

## Branch model

| Branch | Purpose |
| ------ | ------- |
| `main` | Tracks `rebornix/Agmente` **verbatim**. Never commit here directly. |
| `fork` | Long-lived fork line — **default branch**. All our work lands here. |

Keeping `main` pristine makes rebasing `fork` onto new upstream trivial.

### Rebasing on upstream

```bash
git remote add upstream https://github.com/rebornix/Agmente.git   # once
git fetch upstream
git checkout main && git merge --ff-only upstream/main
git push origin main
git checkout fork && git rebase main        # replay our commits on new upstream
git push --force-with-lease origin fork
```

Our fork touches few files (bundle ID / display name in the pbxproj, `.github/`,
`docs/FORK.md`, the signing example), so conflicts are rare and small.

### PR-upstream policy

Only send PRs to `rebornix/Agmente` for **protocol-general** fixes — things any
Agmente user benefits from (ACP handling, UI bugs, crashes). Fork-identity
commits (bundle ID, TestFlight workflow) stay in the fork and are never
proposed upstream.

## Fork identity

| What | Value | Where to change |
| ---- | ----- | --------------- |
| Bundle ID (app) | `com.jedwards1230.gofer-client` | `Agmente.xcodeproj/project.pbxproj` → `PRODUCT_BUNDLE_IDENTIFIER` (app target, Debug + Release) |
| Display name | `Gofer` | `Agmente.xcodeproj/project.pbxproj` → `INFOPLIST_KEY_CFBundleDisplayName` (app target, Debug + Release) |
| Signing team | *(local, gitignored)* | `Agmente/Config/Signing.local.xcconfig` |

> **Trademark note.** The display name and any App Store Connect listing must
> not use rebornix's "Agmente" name or marks. `Gofer` is the default. If you
> rename, change **both** `INFOPLIST_KEY_CFBundleDisplayName` lines together and
> keep the bundle ID stable (renaming the bundle ID orphans the TestFlight app
> record).

## Building locally

Requires **Xcode 16+** (Swift 6 tools, iOS 18 deployment target).

```bash
git clone https://github.com/jedwards1230/Agmente.git
cd Agmente
cp Agmente/Config/Signing.local.xcconfig.example Agmente/Config/Signing.local.xcconfig
# edit Signing.local.xcconfig → set AGMENTE_DEVELOPMENT_TEAM to your Team ID
open Agmente.xcodeproj
# select the Agmente scheme + your device, then Run (⌘R)
```

No secrets are needed to build. Remote SPM dependencies resolve from
`Package.resolved` on first build.

- **Free Apple ID:** installs on your own device but the signature expires
  after 7 days (re-run from Xcode to renew).
- **Paid Apple Developer account:** signs for ~1 year, and is required for
  TestFlight distribution to family.

### Unsigned command-line build (what CI runs)

```bash
xcodebuild build \
  -project Agmente.xcodeproj \
  -scheme Agmente \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

## CI

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) builds and tests the
app on an **unsigned iOS Simulator** for every push and PR to `fork`. It runs on
GitHub-hosted `macos-15` runners (free minutes on a public repo) and needs **no
secrets** — signing is disabled for the simulator. All third-party actions are
SHA-pinned.

## TestFlight release setup (one-time, manual)

[`.github/workflows/release-testflight.yml`](../.github/workflows/release-testflight.yml)
archives, signs (App Store Connect **cloud-managed signing**), and uploads a
build to **TestFlight internal testing**. It is a scaffold — it will fail until
you do the following once. All of this is done by hand in Apple's portals; the
repo only ever stores placeholders.

1. **Enroll** in the Apple Developer Program (paid) if you haven't. Note your
   **Team ID** (`developer.apple.com/account` → Membership).

2. **Create the app record** in [App Store Connect](https://appstoreconnect.apple.com)
   → Apps → **＋** → New App:
   - Platform: iOS
   - Bundle ID: `com.jedwards1230.gofer-client` (register it first under
     Certificates, Identifiers & Profiles → Identifiers if it isn't listed)
   - Name: a name that is **yours**, not "Agmente" (e.g. `Gofer`)
   - SKU: any unique string (e.g. `gofer-client`)

3. **Create an App Store Connect API key** (Users and Access → **Integrations**
   / Keys → App Store Connect API → **＋**):
   - Access: **App Manager** (enough to upload builds)
   - Download the `AuthKey_XXXXXXXXXX.p8` **once** (Apple won't let you
     re-download it) and note the **Key ID** and **Issuer ID**.

4. **Add repo secrets** (repo → Settings → Secrets and variables → Actions →
   New repository secret):

   | Secret | Value |
   | ------ | ----- |
   | `ASC_KEY_ID` | the API **Key ID** |
   | `ASC_ISSUER_ID` | the API **Issuer ID** |
   | `ASC_PRIVATE_KEY` | the **full text** of `AuthKey_XXXX.p8` |
   | `AGMENTE_DEVELOPMENT_TEAM` | your **Team ID** |

5. **Add internal testers**: App Store Connect → your app → TestFlight →
   Internal Testing → add your family (they must be added as Users in App Store
   Connect first, or use an internal group). Internal builds skip Beta App
   Review and are available in minutes.

6. **Release a build**: push a tag (`git tag v2026.07.1 && git push origin
   v2026.07.1`) or run the workflow manually (Actions → *Release (TestFlight
   internal)* → Run workflow). Cloud-managed signing creates the distribution
   certificate + provisioning profile on the runner automatically — there is no
   cert or profile to store as a secret.

> **90-day expiry.** TestFlight builds expire 90 days after upload. The
> tag-triggered workflow makes a quarterly re-upload a one-line command — bump
> the tag and push.

## Security

This is a **public** repo. Never commit: your Team ID, ASC key IDs/issuer IDs,
the `.p8` key, provisioning profiles, or any private host names / addresses.
Team ID stays in the gitignored `Signing.local.xcconfig`; ASC credentials stay
in GitHub Actions secrets. Committed files carry placeholders only.
