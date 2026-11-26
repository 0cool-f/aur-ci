# aur-ci

Shared update automation for my AUR packages. The AUR repository stays the only source of each
package; a small public repository per package, named after it without suffixes such as `-bin`,
tells this workflow how to find upstream releases.

## update.yml

A reusable workflow, called with the AUR `pkgbase`:

1. `bump` clones the AUR repository read-only over HTTPS and compares `pkgver` in `.SRCINFO` with
   the version printed by the caller's `ci/latest.sh`, stopping when the package is current.
2. It applies the caller's `ci/update.sh VERSION NOTES` (run inside the AUR checkout) or, when there
   is none, sets `pkgver` and resets `pkgrel`. When `ci/update.sh` prints anything but `match`, it
   opens an issue with NOTES in the caller repository and fails without publishing.
3. It refreshes the checksums, builds the package with `makepkg` and `namcap` in an Arch container
   and rewrites `.SRCINFO`. No secret is available up to this point.
4. `publish`, in the caller's `aur` environment, clones the AUR repository with
   `AUR_SSH_PRIVATE_KEY`, applies the change only if the repository has not moved since `bump`, and
   pushes `chore: update to X` without forcing.

With `dry-run: true` it stops after step 3.

## Updater repository layout

```
ci/latest.sh                    prints the latest downloadable upstream version, or nothing
ci/update.sh                    optional, see above
.github/workflows/update.yml    on: workflow_dispatch, push to main (dry run)
                                uses: 0cool-f/aur-ci/.github/workflows/update.yml@v1
```

The caller grants `contents: read` and `issues: write` and passes `secrets: inherit`. The repository
needs an `aur` environment restricted to `main` with the `AUR_SSH_PRIVATE_KEY` secret. Scheduled runs
come from an external scheduler through `workflow_dispatch`, since GitHub disables `schedule` in
public repositories after 60 days without activity.

## Versions

`v1` is a moving tag for compatible changes; incompatible changes to inputs or the updater layout
get `v2`.

## Local use

```sh
~/repo/system/aur/aur-ci/check/check.sh                 # in an AUR checkout: build, namcap, verify .SRCINFO (needs podman)
~/repo/system/aur/aur-ci/check/check.sh --update-sums   # also refresh checksums and rewrite .SRCINFO
```

Released under the AGPL-3.0-or-later license.
