---
title: LidSwitch Release And Distribution
doc_kind: ops
doc_function: canonical
purpose: Observed packaging, signing, notarization and release safety contract.
derived_from:
  - ../dna/governance.md
status: active
audience: humans_and_agents
---

# Release And Distribution

The shipped unit is a versioned arm64 ZIP containing `LidSwitch.app`, plus its
SHA-256 checksum. The observed latest tag during adoption was `v0.7.0`.

```sh
./Scripts/package-release.sh
```

This builds/signs the app and writes release artifacts under `dist/release/`.
Developer ID signing and notarization use:

```sh
LIDSWITCH_CODESIGN_IDENTITY="Developer ID Application: ..." \
LIDSWITCH_NOTARY_PROFILE="profile-name" \
./Scripts/notarize-release.sh
```

Run the automated profile from [`../engineering/testing-policy.md`](../engineering/testing-policy.md) and the
relevant physical-MacBook acceptance matrix before publication. Creating a
GitHub release or updating Homebrew is a live distribution action and requires
explicit owner approval.

Rollback unit is the complete app archive/version. The repository does not
currently document the precise Homebrew rollback procedure or release approver;
those remain owner-pending gaps.
