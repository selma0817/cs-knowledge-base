---
title: Private IP Public IP and NAT
aliases:
  - Private IP
  - Public IP
  - NAT
  - Network Address Translation
  - Port Forwarding
tags:
  - networking
  - ip
  - nat
  - router
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# Private IP Public IP and NAT

Private IPs are used inside local networks. Public IPs are reachable on the internet. NAT lets many private devices share one public IP.

## Private IP

Common private IP ranges include:

```text
192.168.x.x
10.x.x.x
172.16.x.x - 172.31.x.x
```

Examples:

```text
192.168.1.23   # home laptop
10.0.1.10      # cloud VM private IP
```

Private IPs are not globally routable on the public internet.

## Public IP

A public IP is reachable across the internet, assuming routing and firewall rules allow it.

Examples:

```text
73.42.10.5
142.250.190.14
```

Websites usually see your router's public IP, not your laptop's private IP.

## NAT

NAT means **Network Address Translation**.

Example:

```text
Laptop private: 192.168.1.23:53122
Router public:  73.42.10.5:61001
Google:         142.250.190.14:443
```

The router rewrites the source address and keeps a NAT table:

```text
73.42.10.5:61001 <-> 192.168.1.23:53122
```

When Google replies to `73.42.10.5:61001`, the router maps the response back to the laptop.

## Outbound vs inbound

Outbound traffic is easy:

```text
Laptop -> router NAT -> internet
```

The router creates a temporary NAT table entry.

Random inbound traffic is different. If someone on the internet connects to:

```text
73.42.10.5:8000
```

the router does not know which internal device should receive it unless port forwarding is configured.

## Port forwarding

Port forwarding creates a static rule:

```text
Router public 73.42.10.5:8000
-> Laptop private 192.168.1.23:8000
```

Without port forwarding, home devices are usually not directly reachable from the public internet.

## Interview sentence

> NAT lets private devices share a public IP by rewriting source IP/port pairs and keeping a table that maps replies back to the correct internal device.

## Related

- [[IP Address vs Port]]
- [[Routing Default Gateway and Subnet]]
- [[ARP and MAC Address]]
- [[AWS VPC Networking]]
