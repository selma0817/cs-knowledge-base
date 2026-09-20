---
title: Network Debugging Ladder
aliases:
  - Debugging curl Failures
  - DNS TCP TLS HTTP Debugging
  - Network Failure Layers
tags:
  - networking
  - debugging
  - curl
  - dns
  - tcp
  - tls
  - http
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# Network Debugging Ladder

A useful debugging habit is to identify which layer failed.

```text
DNS -> TCP -> TLS -> HTTP -> Application
```

A later-layer error proves earlier layers mostly worked.

## Failure map

```text
Could not resolve host
-> DNS failed
```

The client could not turn a domain name into an IP address. See [[DNS]].

```text
Connection timed out
-> TCP/network/firewall/routing issue
```

The client tried to connect but did not receive a response in time.

Common causes:

- firewall silently dropping packets
- cloud security group blocking port
- wrong IP
- server down
- route problem
- service overloaded

```text
Connection refused
-> host reachable, but port closed/no listener
```

The machine actively rejected the TCP connection.

```text
TLS certificate error
-> TLS/certificate validation failed
```

Examples:

- expired certificate
- hostname mismatch
- self-signed certificate
- untrusted CA

See [[TLS Certificates and Certificate Authorities]].

```text
HTTP 401
-> not authenticated
```

Missing, invalid, or expired token.

```text
HTTP 403
-> authenticated but not authorized
```

The server knows who the user is but denies permission.

```text
HTTP 404
-> route/resource not found
```

The HTTP server responded, but the requested path or resource was not found.

```text
HTTP 500
-> server application error
```

The application crashed or failed while processing the request.

```text
HTTP 502
-> gateway/proxy upstream error
```

A proxy or load balancer could not get a valid response from the backend.

```text
HTTP 503
-> service unavailable
```

The service may be overloaded, down for maintenance, or have no healthy backends.

## Layer implication

If you see `HTTP 401`, then these likely worked:

```text
DNS worked
TCP worked
TLS worked, if HTTPS
HTTP server responded
authentication failed
```

If you see `certificate hostname mismatch`, then DNS and TCP likely worked, but TLS verification failed.

## EC2 debugging example

Problem:

```bash
# On EC2
curl localhost:8080
# works

# From laptop
curl http://<public-ip>:8080
# times out
```

Likely causes:

1. AWS security group blocks inbound TCP 8080.
2. App listens only on `127.0.0.1:8080`.
3. OS firewall blocks 8080.
4. Docker port is not published.
5. Instance is not in a public subnet or route table is wrong.
6. Wrong public IP.
7. App crashed after local test.

Useful checks:

```bash
ss -tulpen | grep 8080
curl localhost:8080
curl http://<private-ip>:8080
curl -v http://<public-ip>:8080
```

## Related

- [[Network Debugging Tools]]
- [[DNS]]
- [[TCP and Sockets]]
- [[TLS and HTTPS]]
- [[AWS VPC Networking]]
