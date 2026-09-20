---
title: Forward Proxy vs Reverse Proxy
aliases:
  - Forward Proxy
  - Reverse Proxy
  - Proxy
tags:
  - networking
  - proxy
  - system-design
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# Forward Proxy vs Reverse Proxy

A proxy is a network program or service that accepts a connection, optionally inspects or modifies traffic, opens another connection to the next hop, and forwards data.

The difference between a forward proxy and a reverse proxy is whose side it represents.

## Forward proxy

A forward proxy acts on behalf of clients.

```text
Client -> Forward Proxy -> Internet Server
```

It is common in company networks.

It can control:

- which domains employees can access
- logging and monitoring
- malware filtering
- authentication
- outbound traffic policies

Companies enforce forward proxies using:

- device or browser proxy settings
- PAC files
- VPN
- endpoint agents
- firewall rules blocking direct outbound traffic
- transparent proxying

## Reverse proxy

A reverse proxy acts on behalf of servers.

```text
Client -> Reverse Proxy -> Backend App
```

Examples:

- Nginx
- HAProxy
- Envoy
- Traefik
- Caddy
- AWS Application Load Balancer
- Cloudflare

A reverse proxy can handle:

- TLS termination
- request routing
- static files
- rate limiting
- IP allow/block lists
- compression
- security headers
- hiding backend private IPs

## Common reverse proxy deployment

```text
Public internet
  -> Nginx on 0.0.0.0:443
  -> App on 127.0.0.1:3000
```

External users cannot directly access the app on `127.0.0.1:3000`, because for them `127.0.0.1` means their own machine.

## Forward vs reverse summary

```text
Forward proxy:
  protects or controls clients
  Client -> Proxy -> Server

Reverse proxy:
  protects or controls servers
  Client -> Proxy -> Backend
```

## Relation to load balancer

A reverse proxy may also be a [[Load Balancer]] if it distributes requests across multiple backend servers.

## Related

- [[Load Balancer]]
- [[API Gateway]]
- [[TLS and HTTPS]]
- [[Internet Request Lifecycle]]
