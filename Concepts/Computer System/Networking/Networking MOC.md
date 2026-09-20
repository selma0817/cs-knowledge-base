---
title: Networking MOC
aliases:
  - Computer Networking
  - Internet Networking
  - Networking Knowledge Graph
tags:
  - moc
  - networking
  - computer-system
  - interview
created: 2026-07-10
updated: 2026-07-10
status: evergreen
---

# Networking MOC

This map collects the networking concepts needed for software interviews and practical debugging.

## Core request path

- [[Internet Request Lifecycle]]
- [[DNS]]
- [[Routing Default Gateway and Subnet]]
- [[ARP and MAC Address]]
- [[Private IP Public IP and NAT]]
- [[IP Address vs Port]]
- [[Localhost and 0.0.0.0]]
- [[TCP and Sockets]]
- [[Networking Layers Protocols Connections Sockets and Channels]]
- [[UDP]]
- [[TLS and HTTPS]]
- [[TLS Certificates and Certificate Authorities]]

## HTTP and API layer

- [[REST API]]
- [[gRPC]]
- [[HTTP2]]

## Middleboxes and infrastructure

- [[Forward Proxy vs Reverse Proxy]]
- [[Load Balancer]]
- [[API Gateway]]
- [[AWS VPC Networking]]
- [[Kubernetes Service Networking]]
- [[Container]]
- [[Dockerfile vs Docker Compose vs Kubernetes]]

## Debugging

- [[Network Debugging Ladder]]
- [[Network Debugging Tools]]

## Central mental model

When visiting an HTTPS website, the rough path is:

```text
Browser
  -> DNS resolves the domain to an IP
  -> routing table chooses local delivery or default gateway
  -> ARP finds the next-hop MAC address on the local network
  -> IP routing moves packets across networks
  -> TCP creates a reliable byte stream to IP:port
  -> TLS authenticates the server and encrypts the channel
  -> HTTP carries the application request and response
  -> reverse proxy / load balancer / API gateway / backend may process it
```

Interview sentence:

> DNS finds the destination IP, routing chooses the next hop, ARP finds the local MAC address, TCP connects to an IP and port, TLS secures the connection, and HTTP carries the application request and response.

## Learning order

1. [[Internet Request Lifecycle]]
2. [[IP Address vs Port]]
3. [[Localhost and 0.0.0.0]]
4. [[DNS]]
5. [[Routing Default Gateway and Subnet]]
6. [[ARP and MAC Address]]
7. [[TCP and Sockets]]
8. [[TLS and HTTPS]]
9. [[Network Debugging Ladder]]
10. [[AWS VPC Networking]]
11. [[Kubernetes Service Networking]]
