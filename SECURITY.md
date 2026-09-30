# Security Policy

## Threat model

pennylane_client is a client library for the Pennylane Company API v2. These are the security properties the gem has. Each is enforced by tests in `test/`, and [docs/architecture.md](docs/architecture.md) explains how.

- **Tokens.** The gem sends your API token only as an `Authorization: Bearer` header on each request. By default that goes to `https://app.pennylane.com`, over TLS. The token never appears in logs, `inspect` output, exception messages or `on_request` events: errors are built from the response alone, events from the operation and the URL path, and `Request#inspect` filters the header. Rate-limiter state is keyed by a SHA-256 digest of the token, never the token. A token with whitespace or a line break is refused without being echoed (`test/token_secrecy_test.rb`).
- **No unsafe retries.** Pennylane does not enforce idempotency on create operations. The gem never retries a POST, PUT or DELETE after a server error, a timeout or a lost connection, because it cannot know whether the first attempt ran. It retries those only after a 429, or when the caller passes `retry: :always` for that call. `Net::HTTP`'s own retry is turned off.
- **No answer reaches the wrong call.** A call that does not complete, for any reason (a timeout, a lost connection, `Timeout.timeout`, rack-timeout, `Interrupt`), drops its connection. An unread answer is never read as the next call's response, which could be for another token or company. Connections are never shared between threads or fibers.
- **Path parameters cannot reach another operation.** Ids are escaped into the path. A missing, nil or empty id, or one that is exactly `.` or `..`, raises `ArgumentError` before anything is sent, so `find(nil)` cannot read a list and a delete cannot reach the collection. A keyword that names a positional id raises too, so `update(1, id: 2)` cannot write record 2.
- **Hostile response bodies.** An error body that is not valid UTF-8 (a proxy's error page) is read with the bad bytes replaced, so it still raises the error class its status calls for. A 2xx body that is not valid UTF-8 or not JSON raises `PennylaneClient::Error`; it is never scrubbed and returned as data. Error messages are cut at 200 characters.
- **Webhook signatures.** `PennylaneClient::Webhook.verify!` checks the HMAC-SHA256 signature with a constant-time comparison, rejects a timestamp more than 300 s from now in either direction, and raises only `SignatureError` for anything a sender controls. De-duplicating deliveries is the caller's job.
- **Bounded memory per token.** Limiters for tokens no one has used for 60 s are dropped, so rotating tokens or one token per company do not grow memory without bound.
- **No dynamic code.** The gem evaluates no remote or dynamic code and uses no metaprogramming. It has zero runtime dependencies, so there is no transitive dependency surface beyond the Ruby standard library. CI runs `bundler-audit` on the development dependencies.
- **Signed releases.** Releases are published by RubyGems Trusted Publishing with a Sigstore attestation ([docs/releasing.md](docs/releasing.md)). No API key is stored.

Outside the gem's control: how you store tokens and webhook secrets, what you do with returned data, a custom Transport you inject (it sees the raw `Authorization` header and must not log it), a custom limiter, and the security of Pennylane's service.

## Supported versions

| Version | Supported |
| ------- | --------- |
| latest 0.x | Yes |
| older 0.x | No |

## Reporting a vulnerability

Report privately via GitHub Security Advisories: open the **Security** tab and choose **Report a vulnerability**. Do not open a public issue.

This project has one maintainer working best-effort. There is no guaranteed response time, but private reports are read and taken seriously.
