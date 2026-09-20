---
title: IP Address vs Port
aliases:
  - IP vs Port
  - IP Address and Port
  - IP Port Pair
tags:
  - networking
  - ip
  - port
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# IP Address vs Port

An **IP address** identifies a network location or interface. A **port** identifies a service endpoint on that machine.

Example:

```text
142.250.190.14:443
```

means:

```text
IP address: 142.250.190.14
Port:       443
```

Port `443` is commonly used for HTTPS.

## IP address

An IP address answers:

```text
Which machine or network interface should this packet go to?
```

Examples:

```text
192.168.1.23
10.0.1.10
142.250.190.14
```

Some IPs are private, such as `192.168.x.x` and `10.x.x.x`. See [[Private IP Public IP and NAT]].

## Port

A port answers:

```text
Which service on that machine should receive this connection?
```

Examples:

```text
80   -> HTTP
443  -> HTTPS
5432 -> PostgreSQL
6379 -> Redis
8080 -> common development web server
```

A single machine can run multiple network services on different ports.

## IP:port pair

A client usually connects to a pair:

```text
destination IP + destination port
```

For example:

```text
142.250.190.14:443
```

means:

```text
Connect to service listening on port 443 at IP 142.250.190.14.
```

## Relation to TCP sockets

A TCP connection is not identified only by destination IP and port. It is identified by a 4-tuple:

```text
source IP
source port
destination IP
destination port
```

See [[TCP and Sockets]].

## Common confusion

`localhost:8080` and `192.168.1.23:8080` may refer to the same physical laptop, but they are not the same network address.

See [[Localhost and 0.0.0.0]].

## Related

- [[Localhost and 0.0.0.0]]
- [[Private IP Public IP and NAT]]
- [[TCP and Sockets]]
- [[Network Debugging Ladder]]
