---
title: Localhost and 0.0.0.0
aliases:
  - 127.0.0.1
  - localhost
  - 0.0.0.0
  - Bind Address
tags:
  - networking
  - localhost
  - ip
  - docker
  - debugging
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# Localhost and 0.0.0.0

`localhost`, `127.0.0.1`, and `0.0.0.0` are common sources of networking bugs.

## Localhost

```text
localhost
127.0.0.1
```

mean:

```text
this same machine
```

If a server listens on:

```text
127.0.0.1:8080
```

only processes on the same machine can connect to it.

## Private LAN IP

If your laptop has:

```text
192.168.1.23
```

then another device on the same Wi-Fi may be able to reach:

```text
http://192.168.1.23:8080
```

if the app listens on the right interface and firewall allows it.

## 0.0.0.0 as a server bind address

When a server binds to:

```text
0.0.0.0:8080
```

it means:

```text
listen on all IPv4 interfaces
```

This is commonly needed when a service should be reachable from outside the local machine.

## Server-side bind vs client-side destination

`0.0.0.0` is usually a **server-side bind address**, not a client destination.

A client connects to a real destination such as:

```text
127.0.0.1:8080
192.168.1.23:8080
example.com:443
```

## Docker localhost trap

Inside a Docker container:

```text
127.0.0.1
```

means the container itself, not the host machine.

Therefore:

```text
host localhost != container localhost
```

In Docker Compose, one service should usually call another by service name:

```text
redis:6379
```

not:

```text
localhost:6379
```

See [[Kubernetes Service Networking]] for the related Kubernetes service-discovery version.

## Common debugging symptom

On a server:

```bash
curl localhost:8080
```

works, but from your laptop:

```bash
curl http://<server-public-ip>:8080
```

fails.

Possible causes:

- the app is listening only on `127.0.0.1:8080`
- a cloud security group blocks the port
- the OS firewall blocks the port
- Docker port publishing is missing
- the wrong public IP or port is being used

## Related

- [[IP Address vs Port]]
- [[TCP and Sockets]]
- [[Network Debugging Ladder]]
- [[AWS VPC Networking]]
- [[Kubernetes Service Networking]]
