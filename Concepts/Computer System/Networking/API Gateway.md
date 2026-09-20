---
title: API Gateway
aliases:
  - Gateway
  - API Front Door
  - Microservice Gateway
tags:
  - networking
  - api-gateway
  - microservices
  - system-design
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# API Gateway

An API gateway is a specialized reverse proxy for APIs and microservices.

```text
Client
  -> API Gateway
  -> /users    -> user service
  -> /orders   -> order service
  -> /payments -> payment service
```

## Why use an API gateway?

A company may not want every microservice exposed directly to the public internet.

An API gateway provides one controlled public entry point while internal services stay private.

## Common responsibilities

An API gateway often handles:

- authentication
- authorization
- rate limiting
- API keys
- request validation
- request routing
- logging
- metrics
- tracing
- API versioning
- CORS
- quotas
- request/response transformation

## API gateway vs reverse proxy

An API gateway is a kind of [[Forward Proxy vs Reverse Proxy|reverse proxy]], but specialized for API management.

A basic reverse proxy may only route traffic. An API gateway often applies product/API policies such as auth, rate limits, quotas, and analytics.

## API gateway vs internal service calls

External client traffic often goes through the API gateway.

Internal service-to-service traffic may use:

- direct private networking
- service discovery
- gRPC
- message queues
- service mesh

So not all internal calls must pass through the API gateway.

## Relation to Kubernetes Ingress

In Kubernetes, [[Kubernetes Service Networking|Ingress]] defines HTTP routing into a cluster.

An API gateway may overlap with Ingress, but usually provides richer API-management features.

## Related

- [[Forward Proxy vs Reverse Proxy]]
- [[Load Balancer]]
- [[REST API]]
- [[gRPC]]
- [[Kubernetes Service Networking]]
