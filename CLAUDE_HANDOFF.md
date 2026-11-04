# Claude handoff — Trafficity next improvements

**Read this file before making changes.** This handoff resolves the competing-branch confusion and records the verified state as of 2026-11-04.

## Canonical starting point

- Repository: `abdulloh042006-debug/Trafficity`
- Canonical integration branch: `main`
- `main` HEAD at handoff creation: `529899d4e3aefc3c19b78cbf1d84e5a9ee10570d`
- Android application ID: `uz.abdulloh.trafficity`
- The owner wants the next work to continue cleanly from one branch. Use this branch, `claude/next-improvements`, created directly from the current `main`.

## Why the branches looked inconsistent

There were two parallel implementation lineages. PR #5 integrated the selected integration branch into `main`. PR #6 (Codex branch) was closed as a duplicate, but its branch was subsequently pushed to `3fa96d8fa2a384b95cc2d0ab0a4dc4b743bb9a5b`. At handoff:

- `main` = `529899d4e3aefc3c19b78cbf1d84e5a9ee10570d`
- `codex/uzbekistan-expansion` = `3fa96d8fa2a384b95cc2d0ab0a4dc4b743bb9a5b`
- `ccr-7e104e07-0xa8wr` = `3fa96d8fa2a384b95cc2d0ab0a4dc4b743bb9a5b`

The two old branches are **not fast-forward descendants of current main** (GitHub compare reports divergence). Keep them as historical references. Do not force-push, reset, merge either old branch into this branch, or reopen the duplicate PR merely to make the graph look tidy. Their differing commits/files must be inspected individually if any specific change is needed.

## Verification evidence — do not overstate it

- Actions run [41810160068](https://github.com/abdulloh042006-debug/Trafficity/actions/runs/41810160068) completed successfully for exact SHA `5ae608eab215f0938a477c67b6ebac4d1f39ff28`.
- The subsequent `3fa96d8` commit is documented as `[skip ci]`; that run does **not** validate `3fa96d8`.
- The integration checks previously reported for PR #5's head `34c5910d824a62a6a16fc6e22f46b764305628c1` were Flutter 120/120, Node 41/41, Python 55/55, analyzer PASS, package validation PASS and debug APK build PASS.
- Current `main` is merge commit `529899d`, not either of those exact tested SHAs. Do not label the current HEAD itself CI-verified until a workflow for its exact SHA is observed.
- No actual phone/emulator verification is recorded. The owner installed/tested an APK but reported almost no visible change. Treat the user-facing improvement as unverified; do not claim the UI issue is solved.
- Local APK build was previously blocked by missing Android SDK; CI builds the APK.

## Actual product limits to preserve honestly

- Detailed playable road data exists only for Tashkent City (16 chunks).
- The other 13 regions remain `OVERVIEW_ONLY`.
- Region boundary shapes are approximate rectangular envelopes, not official administrative borders.
- SOATO codes are not independently confirmed.
- No in-app region downloader/server exists.
- Profile-specific building visuals are not implemented.
- `road_graph_linker` remains intentionally unwired until a second detailed region has a consumer.

## Next-work instructions

1. Start by inspecting the current `main` tree and this branch's base; do not assume the older branch notes are current.
2. Reproduce and diagnose the owner's report: the installed app looked almost unchanged. Identify the exact visible entry point, screen, HUD state and map behavior that should have changed. Compare the running app path with the intended Uzbekistan region selector integration.
3. Make the smallest concrete, user-visible correction that is supported by the existing design and tests. Avoid speculative new features, placeholder map data, fake borders, or profile visuals presented as real.
4. Add/update widget or integration tests for the actual screen flow, not only headless controller tests. If screenshots/golden tests are practical, capture before/after evidence.
5. Run formatting, analyzer, relevant Flutter tests, Node tests and Python tests. Fix regressions before pushing.
6. Push only to `claude/next-improvements` (or a clearly named child branch based on it). Do not touch `main` directly. Open a PR when the work is coherent and tested.
7. Build a fresh debug APK in CI and report the exact commit SHA and matching successful run. The owner only needs the APK artifact for phone installation; do not make the source ZIP a required deliverable.

## Owner communication

The owner asked that the branch conflict be straightened out and Claude continue the next improvements. Keep instructions concrete and economical. Do not ask the owner to resolve Git history or perform terminal steps. Report what changed, what exact tests passed, what remains unverified, and provide the APK only when its artifact is available.
