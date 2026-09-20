---
title: Internet Request Lifecycle
aliases:
  - What Happens When You Visit a Website
  - Browser Request Path
  - HTTPS Request Lifecycle
tags:
  - networking
  - dns
  - tcp
  - tls
  - http
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# Internet Request Lifecycle

When a browser visits:

```text
https://example.com/users/123
```

it does not immediately send an HTTP request to `example.com`. It first resolves the domain, chooses a route, connects to the server, establishes TLS, and then sends HTTP data.

## High-level flow

```text
Browser
  -> [[DNS]]: example.com -> IP address
  -> [[Routing Default Gateway and Subnet]]: choose next hop
  -> [[ARP and MAC Address]]: find next-hop MAC on the local network
  -> [[TCP and Sockets]]: connect to IP:443
  -> [[TLS and HTTPS]]: verify certificate and encrypt channel
  -> HTTP request
  -> [[Forward Proxy vs Reverse Proxy]] / [[Load Balancer]] / [[API Gateway]]
  -> backend application
```

## Step-by-step

1. **DNS lookup**  
   The browser or operating system asks a configured DNS resolver for the IP address of the domain. See [[DNS]].

2. **Routing decision**  
   The operating system checks whether the destination IP is local. If not, it sends the packet to the [[Routing Default Gateway and Subnet|default gateway]].

3. **Local link delivery**  
   On the local network, the device needs the MAC address of the next hop. It uses [[ARP and MAC Address|ARP]].

4. **TCP connection**  
   The client opens a TCP connection to the destination IP and port, usually port `443` for HTTPS. See [[TCP and Sockets]].

5. **TLS handshake**  
   The server presents a certificate. The browser verifies it and both sides derive symmetric encryption keys. See [[TLS Certificates and Certificate Authorities]].

6. **HTTP request**  
   The browser sends an encrypted HTTP request, such as:

```http
GET /users/123 HTTP/1.1
Host: example.com
```

7. **Server-side handling**  
   A [[Load Balancer]], [[Forward Proxy vs Reverse Proxy|reverse proxy]], [[API Gateway]], or backend service processes the request.

8. **Response path**  
   The response travels back through the same connection. If the client is behind [[Private IP Public IP and NAT|NAT]], the router uses its NAT table to send the response back to the correct private device.

## DNS query vs HTTP request

DNS query:

```text
What IP is example.com?
```

HTTP request:

```http
GET /users/123
Host: example.com
```

[[DNS]] helps find where to connect. HTTP is sent after the network connection exists.

## Interview sentence

> When I visit an HTTPS website, the browser first uses DNS to resolve the domain to an IP, opens a TCP connection to that IP on port 443, performs a TLS handshake to create an encrypted channel, sends the HTTP request through that channel, and a reverse proxy or load balancer may forward the request to an internal backend.

## Related

- [[Networking MOC]]
- [[DNS]]
- [[Routing Default Gateway and Subnet]]
- [[ARP and MAC Address]]
- [[TCP and Sockets]]
- [[TLS and HTTPS]]
- [[Network Debugging Ladder]]
