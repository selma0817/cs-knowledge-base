---
title: Kubernetes Service Networking
aliases:
  - Kubernetes Networking
  - Kubernetes Service
  - Kubernetes Ingress
  - ClusterIP
  - Service Discovery
tags:
  - networking
  - kubernetes
  - service-discovery
  - devops
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# Kubernetes Service Networking

Kubernetes networking is mostly about stable names and controlled reachability for unstable pods.

## Pods are unstable

Pods can:

- crash
- be recreated
- scale up or down
- be replaced during deployments
- receive different IPs over time

Directly calling pod IPs is fragile.

## Service discovery

In Docker Compose, a container may call:

```text
redis:6379
```

In Kubernetes, a pod may call:

```text
redis.default.svc.cluster.local:6379
```

These names solve the service discovery problem:

```text
I want Redis, but I do not want to hardcode Redis's changing pod IP.
```

## Kubernetes Service

A Service provides a stable front door for pods.

```text
Client pod
  -> redis Service: stable DNS name + stable ClusterIP
  -> current ready Redis pod
```

A Service usually has:

- stable DNS name
- stable ClusterIP
- service port
- targetPort
- selector
- endpoints / endpoint slices

## Service selector

A Service might select pods with:

```yaml
selector:
  app: redis
```

If the Redis pod is labeled:

```yaml
labels:
  app: cache
```

then the Service selector does not match the pod. The Service may have no endpoints.

## Port and targetPort

Example Service:

```yaml
ports:
  - port: 6379
    targetPort: 6379
```

`port` is the Service port clients use.  
`targetPort` is the port on the backend pod/container.

If `targetPort` is wrong, the Service forwards traffic to the wrong place.

## Namespace

If an app in namespace `app` calls:

```text
redis:6379
```

it may resolve to:

```text
redis.app.svc.cluster.local
```

If Redis is in namespace `default`, the app may need:

```text
redis.default.svc.cluster.local:6379
```

## Ingress

An Ingress exposes HTTP routes into a Kubernetes cluster.

Instead of exposing many internal services directly:

```text
users-service
orders-service
payments-service
```

a cluster can expose one controlled entry point:

```text
Internet
  -> Load Balancer
  -> Ingress Controller / API Gateway
  -> internal services
```

Example route:

```text
api.example.com/users    -> users-service
api.example.com/orders   -> orders-service
api.example.com/payments -> payments-service
```

Ingress is mostly routing. An [[API Gateway]] often adds richer API-management features such as authentication, rate limiting, and analytics.

## Debugging Redis connection refused

Problem:

```text
Connection refused when connecting to redis:6379
```

Possible causes:

1. Redis Service does not exist.
2. DNS name resolves to the wrong namespace.
3. Service selector does not match Redis pod labels.
4. Service has no endpoints.
5. Service port or targetPort is wrong.
6. Redis pod is not running or not ready.
7. Redis listens only on `127.0.0.1` inside its pod.
8. NetworkPolicy blocks traffic.
9. Redis requires auth or TLS but client uses plain unauthenticated connection.

Useful commands:

```bash
kubectl get svc redis
kubectl describe svc redis
kubectl get endpoints redis
kubectl get pods -l app=redis
kubectl logs <redis-pod>
kubectl exec -it <app-pod> -- nslookup redis
kubectl exec -it <app-pod> -- nc -vz redis 6379
```

## Related

- [[API Gateway]]
- [[Load Balancer]]
- [[AWS VPC Networking]]
- [[Localhost and 0.0.0.0]]
- [[Container]]
- [[Dockerfile vs Docker Compose vs Kubernetes]]
