# Governance

## Current model: solo maintainer (BDFL)

pennylane_client has a single maintainer, David Silva
([@Davidslv](https://github.com/Davidslv)), who acts as benevolent dictator:
the maintainer makes all final decisions about the project: features, releases, API
design, and what gets merged.

This is stated plainly because it is the truth. There is no steering committee,
no voting process, and no formal RFC pipeline. Pretending otherwise would only
mislead contributors about how decisions actually get made.

## How decisions are made

- **Small changes** (bug fixes, documentation, tests): decided in pull request
  review.
- **Larger changes** (features, API changes): discussed first in a GitHub
  issue, as described in [CONTRIBUTING.md](CONTRIBUTING.md). The maintainer
  weighs the discussion and decides.
- **Releases and versioning**: decided by the maintainer, following semantic
  versioning.

Discussion happens in public, on GitHub issues and pull requests. Reasoning for
non-obvious decisions is written down there, so the record is open even though
the final call is one person's.

## How this could evolve

If the project attracts contributors who make sustained, high-quality
contributions, the maintainer intends to grant commit access and share
responsibility — see [MAINTAINERS.md](MAINTAINERS.md) for the path. If the
maintainer group grows beyond two or three people, this document will be
revised to describe a genuinely shared decision-making model. Until then, this
document describes the project as it is, not as it might one day be.
