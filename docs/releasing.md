# Releasing

Releases go to RubyGems by Trusted Publishing from `.github/workflows/release.yml`. No API key is stored anywhere. Each release carries a Sigstore attestation.

## One-time setup

Done once per gem, by the maintainer.

1. Turn on MFA on the rubygems.org account.
2. On rubygems.org, add a **pending trusted publisher** (Profile > OIDC > Pending trusted publishers) for gem `pennylane_client`: repository owner `Davidslv`, repository `pennylane_client`, workflow `release.yml`, environment `release`. After the first release it becomes the gem's trusted publisher.
3. On GitHub, create the `release` environment (Settings > Environments). Optionally require the maintainer's approval and limit it to `v*` tags.

## Each release

1. On a branch, set `PennylaneClient::VERSION` in `lib/pennylane_client/version.rb`.
2. Move the `[Unreleased]` entries in `CHANGELOG.md` under `## [x.y.z] - YYYY-MM-DD`, and update the compare links at the bottom. The gate fails if the version has no dated entry.
3. Merge the pull request with the gate green.
4. Tag the merge commit and push the tag:

   ```sh
   git checkout main && git pull --ff-only
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```

5. The Release workflow checks the tag matches `VERSION`, runs the gate, then publishes. Approve the `release` environment if it asks.

## Check the release

```sh
gem install pennylane_client -v X.Y.Z
gem specification pennylane_client -v X.Y.Z dependencies   # []
```

The attestation shows on the version's page on rubygems.org and under the repository's **Attestations**. `gh attestation verify pennylane_client-X.Y.Z.gem --repo Davidslv/pennylane_client` checks a downloaded `.gem`.

If a release goes wrong, yank it with `gem yank pennylane_client -v X.Y.Z` and ship a new patch version. A yanked version number cannot be reused.
