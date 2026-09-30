# Security Policy

## Threat model

pennylane_client is a client library for the Pennylane Company API v2. **Status: nothing below is built yet.** These are the security properties the gem is designed to have (proposal 0001); each is enforced by tests as it lands:

- **Tokens.** The gem sends your API token only as an `Authorization: Bearer` header to `https://app.pennylane.com`, over TLS. It never writes the token to logs, `inspect` output, exception messages or the `on_request` instrumentation event. Rate-limiter state is keyed by a SHA-256 digest of the token, never the token itself.
- **No unsafe retries.** Pennylane does not enforce idempotency on create operations. The gem never retries a POST, PUT or DELETE after a server error or a network timeout, because it cannot know whether the first attempt ran. It retries those only after a 429, or when the caller opts in.
- **Webhook signatures.** `PennylaneClient::Webhook.verify!` checks the HMAC-SHA256 signature with a constant-time comparison and rejects stale timestamps. Deduplicating deliveries is the caller's job.
- **No dynamic code.** The gem evaluates no remote or dynamic code and has zero runtime dependencies, so there is no transitive dependency surface beyond the Ruby standard library.

Outside the gem's control: how you store tokens and webhook secrets, what you do with returned data, and the security of Pennylane's service.

## Supported versions

| Version | Supported |
| ------- | --------- |
| latest 0.x (once released) | Yes |
| older 0.x | No |

## Reporting a vulnerability

Report privately via GitHub Security Advisories: open the **Security** tab and choose **Report a vulnerability**. Do not open a public issue.

This project has one maintainer working best-effort. There is no guaranteed response time, but private reports are read and taken seriously.
