---
title: ARP and MAC Address
aliases:
  - Address Resolution Protocol
  - MAC Address
  - IP vs MAC
tags:
  - networking
  - arp
  - mac-address
  - link-layer
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# ARP and MAC Address

ARP means **Address Resolution Protocol**. It maps a local IP address to a MAC address.

## IP vs MAC

```text
IP address:
  logical network-layer address
  used across networks

MAC address:
  link-layer address
  used for one local hop
```

Example:

```text
IP:  192.168.1.23
MAC: a4:83:e7:12:9c:aa
```

## What ARP answers

ARP answers:

```text
I know the local IP. What is the MAC address?
```

Example ARP request:

```text
Who has 192.168.1.1?
Tell 192.168.1.23.
```

Example ARP reply:

```text
192.168.1.1 is at aa:bb:cc:dd:ee:ff.
```

## Same-subnet traffic

If your laptop is:

```text
192.168.1.23/24
```

and wants to reach:

```text
192.168.1.50
```

it ARPs for `192.168.1.50` and sends directly to that device's MAC address.

## Internet traffic

If your laptop wants to reach:

```text
8.8.8.8
```

it does **not** ARP for `8.8.8.8`, because `8.8.8.8` is not local.

Instead, it uses the default gateway:

```text
192.168.1.1
```

and ARPs for the router's MAC address.

## Key distinction

```text
MAC address changes hop by hop.
IP destination usually remains the final destination.
```

For a packet to Google:

```text
Local Wi-Fi frame:
  destination MAC = router MAC

IP packet:
  destination IP = Google IP
```

## Related

- [[Routing Default Gateway and Subnet]]
- [[Private IP Public IP and NAT]]
- [[Internet Request Lifecycle]]
