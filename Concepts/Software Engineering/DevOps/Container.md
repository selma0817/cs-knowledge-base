---
date: 2026-07-06
aliases:
  - Docker Container
  - Podman Container
tags:
  - os-process
  - devops
---

## What Is a Container?

A **container** is a running, isolated environment created from a Docker image.

At the Docker level:

```text
image = packaged template
container = running instance of the image
```

At the operating system level, a container is not a full virtual machine. It is one or more normal host processes running with isolation mechanisms such as namespaces, cgroups, and an isolated filesystem view.

A more precise definition is:

```text
A container is an isolated group of processes started from an image.
```

Usually, a container has one main process. That process is PID 1 inside the container. When the main process exits, the container usually stops.

For example:

```text
nginx image
  -> nginx container
  -> nginx server process

postgres image
  -> postgres container
  -> postgres database process

python app image
  -> python app container
  -> python server process
```

The relationship is:

```text
Dockerfile -> image -> container -> running process
```

A container is therefore both:

```text
a running instance of an image
```

and, more precisely:

```text
an isolated process environment managed by the container runtime
```

Images do not run directly. Containers run from images. Processes run inside containers.

## Related notes

- [[Dockerfile vs Docker Compose vs Kubernetes]]