---
date: 2026-06-26
aliases:
  - JSON Web Token
tags:
  - authentication
  - security
  - web
  - networking
---

A **JWT** is a compact, self-contained, digitally signed token that carries a set of claims (facts about a user or session) and can be verified by any party holding the right key — without consulting a database. It is the dominant mechanism for stateless [[Authentication]] and [[Authorization]] in modern web APIs and [[Microservices]].

## The problem it solves

[[HTTP]] is **stateless**: every request is independent and carries no memory of previous ones. After a user logs in, the server must re-establish _who they are_ on every subsequent request. Something must therefore travel with each request to prove identity, and the server must have a way to trust that proof.

## Two approaches to carrying identity

There are two broad strategies, and JWT is best understood by contrast with the older one.

||[[Session-based Authentication]]|Token-based (JWT)|
|---|---|---|
|Where identity lives|Server-side, in a [[Session Store]]|Inside the token, on the client|
|What the cookie holds|An opaque [[Session ID]] (a _pointer_)|The full self-describing token|
|Per-request work|A lookup in the shared store|Local cryptographic verification|
|Shared infrastructure|A live, mutable store every instance queries|A static secret (or public key)|
|Logout / [[Token Revocation]]|Trivial — delete the store entry|Hard — server stores nothing to delete|

The session model keeps the _state_ on the server and hands the client only a reference. The JWT model puts the _state in the token itself_ and keeps nothing server-side, trading away easy revocation for stateless scalability.

## Anatomy of a token

A JWT is three [[Base64|base64url]]-encoded parts joined by dots:

```
header.payload.signature
```

- **Header** — JSON describing the token: the signing algorithm and type, e.g. `{"alg":"HS256","typ":"JWT"}`.
- **Payload** — JSON holding the **claims**, e.g. `{"sub":"user-123","exp":1782589178,"iat":1782502778,"role":"user"}`.
- **Signature** — the output of signing `header + "." + payload` with a key (see below).

> A JWT is **encoded, not encrypted.** [[Base64]] is a reversible encoding, not a cipher. Anyone holding the token can decode and read the payload with no key. The signature prevents _modification_, not _reading_. **Never place secrets or sensitive data (passwords, API keys, anything confidential) in a JWT payload** — treat it as public. (An encrypted variant, [[JWE]], exists for when confidentiality of the claims is required.)

## The signature: integrity, not secrecy

The signature is what makes a client-held, self-describing token trustworthy. It is produced by a keyed one-way function — commonly [[HMAC]] with [[SHA-256]] (the `HS256` algorithm) — over the header and payload, using a secret key.

**Verification** does not "decode" the signature. The server **recomputes** the signature from the received header and payload using its key, then compares the result against the signature attached to the token. If they match, the payload is authentic and unmodified; if not, it is rejected.

This yields a precise security property worth memorizing:

- **Protects against tampering / forgery.** An attacker cannot change a claim (e.g. elevate `role` to `admin`) or mint a new token, because they cannot produce a matching signature without the key.
- **Does _not_ protect against theft.** A stolen, unmodified token is fully valid for whoever presents it. This is the [[Bearer Token]] model — like cash, possession equals authority. Defences against theft live _outside_ the token (TLS, secure storage, short lifetimes).

### Signing algorithms: symmetric vs asymmetric

- **HS256 (symmetric)** — the _same_ [[Secret Key]] both signs and verifies. Simple, but every verifier can also mint tokens, so the secret must be guarded everywhere it lives.
- **RS256 (asymmetric, [[Asymmetric Cryptography]])** — a **private key** signs, a **public key** verifies. Verifiers can validate tokens without being able to create them. Preferred when many independent services must verify but only one issuer should sign.

## Claims and expiry

The payload holds standard _registered claims_ alongside any custom ones. The most important for security:

- `exp` — **expiration time** (a Unix timestamp). The server rejects the token once the current time passes `exp`.
- `iat` — issued-at time. `nbf` — not-valid-before. `sub` — subject (the user). `iss` / `aud` — issuer / audience.

Because `exp` lives _inside the signed payload_, a token carries its own deadline: the server needs no stored TTL to expire it, and the client cannot extend it (changing `exp` would invalidate the signature). **This is how a stateless token dies without any server-side record.**

## The statelessness tradeoff

Verification of a token requires only the key, already in each server's memory — no per-request lookup against a shared store. This is the central benefit:

- **Horizontal scale.** Any number of server instances behind a [[Load Balancer]], or any number of independent [[Microservices]], can each verify a token locally by holding the same secret (or the issuer's public key). No shared session database sits on the per-request path.

The cost is the mirror image:

- **No easy revocation.** The server stores nothing about issued tokens, so there is no record to delete to invalidate one before its `exp`. (See [[Token Revocation]].)
- **No sliding expiration.** A token's `exp` is fixed at issue time; activity cannot extend a single token's life.

A useful summary: **pure access-token verification is stateless per request.**

## Refresh tokens: restoring liveness and revocation

The standard resolution to the two costs above is a **two-token split**:

- **Access token** — short-lived (minutes). Sent with _every_ request, so maximally exposed; kept short so a stolen one is near-worthless quickly. Verified statelessly (signature + `exp`), no lookup.
- **Refresh token** — long-lived (days/weeks). Sent _only_ to a dedicated refresh endpoint, so rarely exposed. Its sole power is to obtain new access tokens.

**Flow.** On login the client receives both. When the access token expires, the client silently sends the refresh token to the refresh endpoint and receives a fresh access token — producing **sliding login** for active users without re-entering credentials.

**Revocation.** Because refresh tokens are long-lived and hit a single rare endpoint, it is practical to track them in a server-side store (a list of valid tokens, or a blocklist of revoked ones). To log a user out, invalidate their refresh token: their current access token keeps working until it expires (a window equal to the access token's lifetime), after which they can no longer obtain a new one and are locked out.

**Verification of a refresh token** therefore has two steps:

1. **Authenticity** — if the refresh token is itself a JWT: signature + `exp`. (Refresh tokens are often **opaque random strings** instead, with no claims and nothing to verify cryptographically.)
2. **Still-valid?** — a mandatory lookup in the server-side store. This lookup _is_ the revocation mechanism.

The key architectural consequence: **the system is stateless per request but stateful per refresh.** A shared store reappears, but only on the rare refresh path — not on every API call. Multiple servers handling refresh must connect to that same shared store; servers verifying access tokens need only the shared key. Compared to full sessions, the shared-store dependency is relocated _off the hot path_, which is the real, defensible benefit — not "no shared state ever."

## When to use, when to avoid

- **Good fit:** stateless APIs, multi-instance deployments behind a load balancer, [[Microservices]] where many services must verify identity independently, and any case where avoiding a per-request session lookup matters for scale.
- **Poor fit (or use with care):** systems requiring _instant_ revocation (e.g. banking), where server-side sessions or a strict blocklist are simpler and safer; and small single-server apps, where session-based auth is often less complex than managing access/refresh token machinery.

## Client-side storage (brief)

Where the token is kept on the client is its own security tradeoff: an `HttpOnly` + `Secure` cookie protects against script theft ([[XSS]]) but is exposed to [[CSRF]]; `localStorage` is convenient but readable by any injected script. See [[Cookies]], [[XSS]], [[CSRF]].

## Open questions / to explore

- When is RS256 (asymmetric) worth its complexity over HS256 (symmetric)?
- Best practice for client-side token storage given the XSS vs CSRF tradeoff?
- Refresh-token **rotation** (issuing a new refresh token on each use) and reuse-detection.
- [[JWE]] — when do you actually need encrypted (not just signed) claims?

## Related

- [[Authentication]] 
- [[Authorization]]
- [[Session-based Authentication]]
- [[Bearer Token]] 
- [[HMAC]] 
- [[SHA-256]] 
- [[Base64]] 
- [[Asymmetric Cryptography]] 
- [[Token Revocation]] 
- [[HTTP]] 
- [[Microservices]] 
- [[OAuth]] 
- [[Cookies]] 
- [[XSS]] 
- [[CSRF]]