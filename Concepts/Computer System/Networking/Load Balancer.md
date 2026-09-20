---
title: Load Balancer
aliases:
  - Load Balancing
  - Layer 4 Load Balancer
  - Layer 7 Load Balancer
  - L4 Load Balancer
  - L7 Load Balancer
tags:
  - networking
  - load-balancer
  - system-design
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# Load Balancer

A load balancer distributes traffic across multiple backend targets.

```text
Client
  -> Load Balancer
  -> Backend A / Backend B / Backend C
```

## Why use a load balancer?

Load balancers provide:

- scalability
- reliability
- health checks
- backend hiding
- deployment flexibility
- TLS termination
- path or host routing, for Layer 7 load balancers

## Layer 4 load balancer

A Layer 4 load balancer works at the TCP/UDP level.

It mainly sees:

```text
source IP/port
destination IP/port
transport protocol
```

It routes connections rather than interpreting HTTP paths.

Example:

```text
TCP connection -> backend server
```

## Layer 7 load balancer

A Layer 7 load balancer works at the application protocol layer, usually HTTP.

It can route based on:

- hostname
- path
- headers
- cookies
- HTTP method

Example:

```text
GET /users  -> users-service
GET /orders -> orders-service
```

A Layer 7 load balancer is often also a [[Forward Proxy vs Reverse Proxy|reverse proxy]].

## DNS load balancing vs load balancer

DNS may return multiple IPs for one domain. That is DNS-based distribution.

A load balancer is an actual network service in the request path:

```text
DNS: api.example.com -> load balancer IP
Client -> load balancer -> backend
```

## 502 and 503

`502 Bad Gateway` often means the load balancer or proxy could not get a valid response from an upstream backend.

`503 Service Unavailable` often means no healthy backend is available or the service is overloaded/temporarily unavailable.

See [[Network Debugging Ladder]].

## Related

- [[Forward Proxy vs Reverse Proxy]]
- [[API Gateway]]
- [[AWS VPC Networking]]
- [[Kubernetes Service Networking]]
