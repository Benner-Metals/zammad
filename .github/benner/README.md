# Benner Metals Zammad build

`benner/7.2` is upstream Zammad 7.2 `stable` plus the commits below. CI publishes it as
`ghcr.io/benner-metals/zammad:<upstream build>-bm<N>`.

| Commit                                                                           | Source                   |
| -------------------------------------------------------------------------------- | ------------------------ |
| Feature: Add a move-to-folder action for Microsoft Graph email.                  | `224a7b6217`             |
| Fix: Persist content-specific receipts for Microsoft Graph move retries.         | `ed98ed81c2`             |
| Maintenance: Separate move helpers from cloud endpoint changes.                  | `f3532ed12b`             |
| Preserve Graph retry receipts and isolate failed imports                         | `93d6c4eb3f`             |
| Send oversized Graph rejection mail outside receipt transactions                 | `bde4e97e2c`             |
| Feature: Add GCC High support to Microsoft mail channels and sign-in.            | `94564c98de`             |
| Fix: Scope Microsoft channel secret rotation to its app and cloud.               | `857e7512b8`             |
| Test: Refresh commercial channels after switching Microsoft cloud configuration. | `bf29207d4c`             |
| Rotate Microsoft app secrets across tenant authorities                           | `c5e293fa6f`             |
| Test: Cover Microsoft Graph move mode together with national clouds.             | `ac273cca9f` (spec only) |
| Maintenance: Build the Benner Metals image and watch upstream.                   | Benner only              |

The move commits are the complete range of `zammad-graph-move-to-folder` at `bde4e97e2c` and the
cloud commits that of `zammad-national-cloud` at `c5e293fa6f`; their combination matches
`zammad-cloud-move-integration` at `ac273cca9f`.

Both features are also proposed upstream. Each picked commit names its source in a
`(cherry picked from commit …)` line.

## Image tags

- `<upstream build>` is the upstream build the branch is based on, computed with upstream's own
  formula: `7.2.0-0021` is the same commit as `ghcr.io/zammad/zammad:7.2.0-0021`. Once upstream
  moves 7.2 to `stable-7.2`, it publishes images only for release tags such as `7.2.1`, so later
  `<upstream build>` values name no official image.
- `bm<N>` counts Benner builds on that upstream build, starting at 1. Before pushing an image, a
  build reserves its number by pushing the git tag `benner/<image tag>` on its source commit, so a
  number is never used twice. A failed build can leave a reserved number without an image.
- The image carries the labels `com.bennermetals.zammad.upstream-base`, `…upstream-build` and
  `…benner-commits`, and Zammad's version string ends in `.<image tag>.docker`.

## Workflows

- **benner-image** runs on every push to `benner/7.2` and on demand. It runs
  [`specs.sh`](specs.sh) and the catalog check, then builds `linux/amd64` and pushes. A commit
  with a published reservation is not rebuilt; otherwise it gets a new number, and the run
  summary records the digest. Re-run all jobs, not only the image job: a partial re-run reuses
  the earlier reservation and stops.
- **benner-upstream-watch** runs every four hours. It compares the branch with upstream `stable`,
  or `stable-7.2` once upstream has moved to a newer line, test-rebases onto it and opens one
  `benner-upstream` issue per new upstream build or release line. Scheduled workflows run only on
  the default branch, so `benner/7.2` must be the default branch and Issues must be enabled. Set
  the repository variable `BENNER_ALERT_ASSIGNEE` to assign the issues.

Only the job that reserves image tags can write to the repository, and it runs no third-party
actions. Third-party actions are pinned to commit SHAs, so update them deliberately.

## Update to a new upstream build

1. In a Zammad checkout of `benner/7.2` with a working `bundle exec rails`, run
   [`rebase-onto-upstream.sh`](rebase-onto-upstream.sh). It regenerates `i18n/zammad.pot` at
   every catalog conflict. On any other conflict it stops and names the command that continues
   once the files are resolved and added.
2. Run [`specs.sh`](specs.sh), then `git push --force-with-lease origin benner/7.2`.
3. **benner-image** publishes `<new upstream build>-bm1`.
4. Take backups, then bump the image in gitops (runbook §5.2).

## Return to the official image

Once an official release contains both features, production switches back to
`ghcr.io/zammad/zammad`. Check first that upstream reads the data this build stores:

- Graph channels in move mode keep `post_import_action: move`, `move_to_folder_id` and
  `keep_on_server: false` in their inbound options. An image without move-to-folder reads only
  `keep_on_server` and **deletes** imported messages from those mailboxes, so never run such an
  image, including a stock rollback, against move-mode channels.
- The Microsoft cloud is stored as `cloud` (`global` or `us_gov`) in the app credentials, each
  channel's auth data and Graph channels' inbound options; IMAP and SMTP channels use that
  cloud's hosts.
- Migration `20260930120000_add_microsoft_cloud_selection` adds the `cloud` field to the Microsoft
  365 sign-in setting and skips it when present. If upstream ships the change under another
  migration or other names, reconcile the stored data before switching.
