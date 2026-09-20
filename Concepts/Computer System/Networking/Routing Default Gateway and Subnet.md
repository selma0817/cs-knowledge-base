---
title: Routing Default Gateway and Subnet
aliases:
  - Routing Table
  - Default Gateway
  - Subnet
  - CIDR
  - Subnet Mask
tags:
  - networking
  - routing
  - subnet
  - gateway
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# Routing Default Gateway and Subnet

After [[DNS]] gives a destination IP, the operating system must decide where to send the packet next.

That decision is made using the routing table.

## Subnet

Example device configuration:

```text
Laptop IP:        192.168.1.23
CIDR:             /24
Subnet:           192.168.1.0/24
Default gateway:  192.168.1.1
```

`/24` means the first 24 bits are the network part. In this example, local addresses include:

```text
192.168.1.1
192.168.1.23
192.168.1.50
192.168.1.254
```

## Local destination

If the destination is:

```text
192.168.1.50
```

the laptop sees that it is in the same subnet. It sends directly on the local network after using [[ARP and MAC Address|ARP]] to find the destination MAC address.

## Non-local destination

If the destination is:

```text
8.8.8.8
```

the laptop sees that it is outside the local subnet. It sends the packet to the default gateway:

```text
192.168.1.1
```

The default gateway is usually the home router, office router, or cloud router.

## Default gateway

The default gateway is the next-hop router used when no more specific route matches.

Simplified rule:

```text
same subnet -> send directly
outside subnet -> send to default gateway
```

## Local frame vs final IP destination

For internet traffic, the local frame is addressed to the router's MAC address, but the IP packet still has the final destination IP.

```text
Wi-Fi/Ethernet frame:
  destination MAC = router MAC

IP packet inside:
  destination IP = 8.8.8.8
```

MAC addresses change hop by hop. IP destination usually remains the final destination, except when NAT rewrites addresses.

## Related

- [[DNS]]
- [[ARP and MAC Address]]
- [[Private IP Public IP and NAT]]
- [[Network Debugging Ladder]]
- [[AWS VPC Networking]]
