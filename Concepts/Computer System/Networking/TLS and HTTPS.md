---
title: TLS and HTTPS
aliases:
  - HTTPS
  - TLS
  - HTTP over TLS
  - TLS Termination
tags:
  - networking
  - security
  - tls
  - https
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# TLS and HTTPS

HTTPS is HTTP over TLS.

TLS provides:

```text
Encryption: outsiders cannot read HTTP content
Integrity: outsiders cannot secretly modify data
Authentication: browser can verify server identity
```

## HTTPS stack

```text
HTTP
TLS
TCP
IP
Wi-Fi/Ethernet
```

HTTP messages are encrypted by TLS before being sent over TCP.

## What HTTPS encrypts

HTTPS encrypts:

- HTTP path
- query string
- headers
- cookies
- authorization tokens
- JSON body
- response body

Outsiders may still see:

- destination IP
- port, usually `443`
- DNS lookup domain
- TLS SNI domain in many cases
- packet size and timing

Even though paths and query strings are encrypted in transit, secrets should not be put in URLs because URLs can leak through logs, browser history, analytics, screenshots, and referrer headers.

## TLS handshake

Modern TLS usually does three conceptual jobs:

1. authenticate the server using a certificate
2. derive shared symmetric keys
3. use those keys to encrypt application traffic

See [[TLS Certificates and Certificate Authorities]] for certificate verification.

## ECDHE, HKDF, and symmetric encryption

```text
ECDHE:
  creates a shared secret during the handshake

HKDF:
  derives usable traffic keys from the shared secret

AES-GCM / ChaCha20-Poly1305:
  encrypts actual HTTP traffic
```

The symmetric key is not sent over the network. Both sides independently derive it from an ephemeral Diffie-Hellman exchange.

## TLS termination

If a load balancer terminates TLS:

```text
Client --HTTPS--> Load Balancer --HTTP--> Backend
```

then TLS ends at the load balancer. The backend may receive plain HTTP.

A second TLS connection may also be used:

```text
Client --HTTPS--> Load Balancer --HTTPS--> Backend
```

## Interview sentence

> TLS uses asymmetric cryptography during the handshake to authenticate the server and establish shared keys, then uses fast symmetric encryption like AES-GCM or ChaCha20-Poly1305 to encrypt the actual HTTP traffic.

## Related

- [[TLS Certificates and Certificate Authorities]]
- [[TCP and Sockets]]
- [[Internet Request Lifecycle]]
- [[Forward Proxy vs Reverse Proxy]]
- [[Load Balancer]]
