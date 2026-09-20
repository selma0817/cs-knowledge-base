---
title: Network Debugging Tools
aliases:
  - ping
  - curl
  - dig
  - nslookup
  - traceroute
  - ss
  - netstat
tags:
  - networking
  - debugging
  - tools
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# Network Debugging Tools

Different tools test different layers of the network stack.

## dig / nslookup

Used for DNS debugging.

```bash
dig api.example.com
nslookup api.example.com
```

Check:

- whether the name resolves
- A/AAAA records
- TTL
- which resolver answered

You can query a specific resolver:

```bash
dig @8.8.8.8 api.example.com
dig @1.1.1.1 api.example.com
```

## ping

Used for basic IP reachability and latency.

```bash
ping google.com
```

Ping uses ICMP, not TCP.

Ping can show:

- whether ICMP echo replies return
- approximate round-trip latency
- packet loss

Ping failure does not always mean a website is down, because many servers and firewalls block ICMP.

## curl

Used to test HTTP/TLS behavior.

```bash
curl -v https://api.example.com/users/123
```

`curl -v` can show:

- DNS resolution
- IP connected to
- TCP connection attempt
- TLS certificate details
- HTTP request headers
- HTTP response status and headers

## ss / netstat

Used on a server to check listening ports.

```bash
ss -tulpen | grep 8080
```

Important distinction:

```text
127.0.0.1:8080 -> local machine only
0.0.0.0:8080   -> all IPv4 interfaces
```

Common flags for `ss`:

```text
-t  TCP
-u  UDP
-l  listening sockets
-p  process info
-e  extended info
-n  numeric addresses/ports
```

## traceroute

Shows the approximate router path to a destination.

```bash
traceroute 8.8.8.8
```

The first hop at home is usually the home router/default gateway.

`traceroute` works by sending packets with increasing TTL values and observing which routers report that the TTL expired.

Some routers do not respond, so `* * *` does not always mean the network is broken.

## Tool mapping

```text
DNS problem?
  dig / nslookup

Basic reachability / latency?
  ping

HTTP/TLS/API behavior?
  curl -v

Is service listening on server?
  ss / netstat

Where does the route seem to stop?
  traceroute
```

## Related

- [[Network Debugging Ladder]]
- [[DNS]]
- [[Routing Default Gateway and Subnet]]
- [[TCP and Sockets]]
