---
title: DNS
aliases:
  - Domain Name System
  - DNS Resolver
  - DNS Lookup
  - A Record
  - CNAME
tags:
  - networking
  - dns
  - interview
  - debugging
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# DNS

DNS means **Domain Name System**. It maps human-readable names to records, especially IP addresses.

Example:

```text
github.com -> 140.82.x.x
```

## What DNS answers

DNS can return different record types:

```text
A      -> IPv4 address
AAAA   -> IPv6 address
CNAME  -> alias to another domain name
MX     -> mail server
TXT    -> text records, often used for verification
```

For web browsing, `A`, `AAAA`, and `CNAME` records are common.

## DNS resolver

A browser usually does not directly ask the authoritative server for a domain. It asks a configured DNS resolver first.

Common resolvers include:

- home router
- ISP DNS
- Cloudflare DNS `1.1.1.1`
- Google DNS `8.8.8.8`
- company DNS
- cloud provider DNS inside cloud networks

A home router may act as a DNS forwarder:

```text
Laptop -> home router -> ISP/public resolver -> DNS hierarchy
```

## DNS caching and TTL

DNS answers can be cached. A DNS record has a TTL, or time to live.

Example:

```text
api.example.com -> 1.2.3.4
TTL: 300 seconds
```

This means clients and resolvers may cache the answer for 300 seconds.

If the IP changes but clients still have a cached old answer, they may keep connecting to the old IP until the TTL expires.

## DNS vs HTTP redirect

DNS does not perform HTTP redirects.

DNS stale cache:

```text
client connects to old IP
```

HTTP redirect:

```text
server responds with 301/302 and a new URL
```

These are different mechanisms.

## Debugging DNS

If `curl` says:

```text
Could not resolve host
```

the failure is at DNS/name resolution.

Useful tools:

```bash
dig api.example.com
nslookup api.example.com
dig @8.8.8.8 api.example.com
dig @1.1.1.1 api.example.com
```

See [[Network Debugging Tools]].

## Related

- [[Internet Request Lifecycle]]
- [[Routing Default Gateway and Subnet]]
- [[Network Debugging Ladder]]
- [[Network Debugging Tools]]
