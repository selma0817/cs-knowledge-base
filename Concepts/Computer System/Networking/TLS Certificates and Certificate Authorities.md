---
title: TLS Certificates and Certificate Authorities
aliases:
  - TLS Certificate
  - Certificate Authority
  - CA
  - X.509 Certificate
  - Certificate Chain
tags:
  - networking
  - security
  - tls
  - certificates
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# TLS Certificates and Certificate Authorities

A TLS certificate is a signed identity document for a server/domain.

It roughly says:

```text
Domain: bank.com
Public key: server public key
Issuer: Certificate Authority
Valid from: date A
Valid until: date B
Signature: CA signature
```

## Certificate authority

A Certificate Authority, or CA, is an entity trusted by browsers and operating systems to sign certificates.

A certificate chain looks like:

```text
bank.com certificate
  signed by Intermediate CA
    signed by Root CA trusted by browser/OS
```

The browser verifies signatures up the chain.

## What the browser checks

When visiting:

```text
https://bank.com
```

the browser checks:

- certificate domain matches `bank.com`
- certificate chain leads to a trusted root CA
- certificate is not expired
- certificate is not revoked
- server proves it owns the matching private key

## Domain match

The certificate contains Subject Alternative Names, or SANs.

Example:

```text
Valid for:
  bank.com
  www.bank.com
```

If the browser visits `bank.com` but receives a certificate for `evil.com`, it rejects the connection.

## Server proves private-key ownership

The certificate contains the server's public key. The server privately holds the matching private key.

During the TLS handshake, the server signs handshake data:

```text
signature = Sign(server_private_key, hash(handshake_messages))
```

The browser verifies the signature using the public key in the certificate:

```text
Verify(server_public_key, hash(handshake_messages), signature)
```

If verification succeeds, the browser knows the server owns the private key corresponding to the certificate.

An attacker can copy the public certificate, but cannot create the correct signature without the private key.

## Why sign handshake messages?

The signature binds together:

```text
certificate identity
+
this specific TLS handshake
+
this specific ECDHE key exchange
```

This prevents a man-in-the-middle attacker from doing separate key exchanges with the browser and the real server while pretending to be the server.

## Common certificate errors

```text
certificate expired
```

The certificate's validity period is over.

```text
certificate hostname mismatch
```

The certificate is not valid for the domain being visited.

```text
self-signed certificate
```

The certificate is signed by itself rather than by a CA the browser trusts.

These are TLS/certificate validation errors, not HTTP status codes.

## Related

- [[TLS and HTTPS]]
- [[Network Debugging Ladder]]
- [[Forward Proxy vs Reverse Proxy]]
