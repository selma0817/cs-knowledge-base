---
date: 2026-06-07
aliases:
  - Dockerfile and Compose
  - Docker Compose
  - Docker Buiild vs Runtime
tags:
  - docker
  - devops
  - containers
  - software-engineering
  - deployment
---
---

## Core distinction

A **Dockerfile** answers:

> How do I build the image for this application?

A **Docker Compose file** answers:

> How do I run this application system?

The most important distinction is:

|Concept|Purpose|
|---|---|
|`Dockerfile`|Builds an **image**|
|`compose.yaml` / `docker-compose.yml`|Runs **containers**|

A Docker image is like a frozen template.  
A container is a running instance of that image.

So the chain is:

```text
Dockerfile -> image -> container
```

Docker Compose usually enters at the container-running stage:

```text
compose.yaml -> run app container + database container + Redis container + networks + volumes
```

## Mental model

A **Dockerfile** is like a recipe.

Example:

```Dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

CMD ["python", "server.py"]
```

This says:

1. Start from a Python base image.
    
2. Set `/app` as the working directory.
    
3. Copy dependency files.
    
4. Install dependencies.
    
5. Copy the project code.
    
6. Run `server.py` when the container starts.
    

It produces an image.

You build it with:

```bash
docker build -t my-app .
```

Then you can run it with:

```bash
docker run -p 8000:8000 my-app
```

## Docker Compose mental model

A Docker Compose file is like a small local deployment configuration.

Example:

```yaml
services:
  web:
    build: .
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgres://user:pass@db:5432/app
    depends_on:
      - db

  db:
    image: postgres:16
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: app
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

This says:

1. Run a `web` service.
    
2. Build the `web` image from the Dockerfile in the current directory.
    
3. Expose port `8000`.
    
4. Pass environment variables into the container.
    
5. Run a `db` service using the official Postgres image.
    
6. Create a persistent volume for database data.
    
7. Let the `web` service refer to the database by the hostname `db`.
    

You start the whole system with:

```bash
docker compose up
```

Or in detached mode:

```bash
docker compose up -d
```

## Relationship between Dockerfile and Compose

They are not competitors. They often work together.

A Compose file can either **build** an image from a Dockerfile:

```yaml
services:
  app:
    build: .
```

or use an already-existing image:

```yaml
services:
  db:
    image: postgres:16
```

So a typical project may have both:

```text
my-project/
  Dockerfile
  compose.yaml
  app/
  requirements.txt
```

The `Dockerfile` describes how to package the app.

The `compose.yaml` describes how to run the app with other services.

## Why Compose is useful

Without Compose, running a multi-container app requires long `docker run` commands.

For example, you might need to manually run:

```bash
docker network create my-network
docker volume create pgdata
docker run ...
docker run ...
```

Compose lets you write the system once in YAML and run everything with:

```bash
docker compose up
```

This is especially useful when an app needs:

- a backend server
    
- a database
    
- Redis
    
- a worker process
    
- a frontend
    
- persistent volumes
    
- environment variables
    
- port mappings
    

## Dialectical distinction

At first, it is tempting to think:

> Dockerfile runs my app.

But more precisely:

> Dockerfile builds the image that contains my app.

Then one might think:

> Docker Compose builds my app.

But more precisely:

> Docker Compose can build images, but its main job is to run and connect containers.

So the cleaner model is:

```text
Dockerfile = build-time definition
Compose file = run-time system definition
```

## Simple analogy

Imagine opening a restaurant.

The **Dockerfile** is the recipe for one dish:

```text
How to make the backend server image.
```

The **Compose file** is the restaurant floor plan:

```text
Run the kitchen, cashier, fridge, database, and delivery worker together.
```

The Dockerfile focuses on one component.

The Compose file focuses on the whole system.

## Common commands

Build an image from a Dockerfile:

```bash
docker build -t my-app .
```

Run one container manually:

```bash
docker run -p 8000:8000 my-app
```

Start a Compose-defined system:

```bash
docker compose up
```

Start in the background:

```bash
docker compose up -d
```

Stop the Compose system:

```bash
docker compose down
```

Rebuild images before starting:

```bash
docker compose up --build
```

## Key takeaway

A `Dockerfile` defines **what the app image is**.

A Docker Compose file defines **how the app system runs**.

In one sentence:

> Use a Dockerfile to package one service; use Docker Compose to run multiple services together.



## One Dockerfile, Multiple Compose Services

A single `Dockerfile` can be reused by multiple services in a Docker Compose file.

For example:

```yaml
services:
  ombre-brain:
    build: .

  ombre-gateway:
    build: .
```

This does **not** mean there are two Dockerfiles. It means both services use the same Dockerfile and the same build context.

The Dockerfile defines the shared image environment:

```text
install dependencies
copy project code
prepare runtime environment
```

The Compose file defines the separate running services:

```text
start ombre-brain container
start ombre-gateway container
connect them with networking
mount volumes
expose ports
pass environment variables
choose commands
```

The key idea:

```text
Dockerfile = build recipe
Compose service = runtime role
Container = running instance
```

So one Dockerfile can produce an image environment that is reused by multiple containers.

In the Ombre-Brain setup, `ombre-brain` and `ombre-gateway` may share the same built environment, but they run as separate containers with separate processes, ports, environment variables, and volumes.

A precise mental model is:

```text
same Dockerfile
same build context
possibly same image content
two Compose services
two separate running containers
```

Images do not run directly. Containers run from images.


## Docker Compose vs Kubernetes

Docker Compose and Kubernetes can both run multi-container applications, but they are not the same kind of tool.

A simple distinction is:

```text
Docker Compose = run multiple containers together, usually on one machine
Kubernetes = orchestrate containers across a cluster, usually for production
```

Docker Compose answers:

> How do I run these services together for local development or a small deployment?

Kubernetes answers:

> How do I keep this application running reliably across machines over time?

## Why They Look Similar

Both tools can describe services such as:

```text
backend
database
redis
worker
frontend
```

Both can define:

```text
container images
environment variables
ports
volumes
networks
service dependencies
```

This is why they can feel similar.

## Key Difference

Docker Compose mainly starts and connects containers.

Kubernetes manages the desired state of an application.

For example, Kubernetes can say:

```text
I want 3 backend replicas running.
If one crashes, restart it.
If a machine dies, move the workload somewhere else.
Expose the backend through a stable service name.
Roll out new versions gradually.
Scale the service up or down.
Separate config and secrets from the image.
```

Compose is usually simpler:

```text
Start this web container.
Start this database container.
Put them on the same network.
Mount these volumes.
Expose these ports.
```

## Build vs Orchestration

Docker Compose can build images directly from a Dockerfile:

```yaml
services:
  app:
    build: .
```

Kubernetes usually does not build images. It expects images to already exist in a container registry:

```yaml
containers:
  - name: app
    image: my-registry/my-app:1.0.0
```

A common Kubernetes flow is:

```text
Dockerfile
-> build image
-> push image to registry
-> Kubernetes pulls image
-> Kubernetes runs containers
```

A common Docker Compose flow is:

```text
Dockerfile
-> Compose builds image
-> Compose runs containers
```

## Are They Replacements?

They are partial replacements, but not perfect replacements.

For local development, Docker Compose often replaces Kubernetes because it is simpler.

For production deployment, Kubernetes often replaces Docker Compose because it has stronger orchestration features.

A practical rule:

```text
Use Docker Compose when learning, developing locally, or running a small single-machine setup.

Use Kubernetes when managing production services, multiple machines, replicas, rolling updates, and failure recovery.
```

## Mental Model

Docker Compose is like a local rehearsal setup:

```text
Run the backend, database, and Redis on my laptop so I can develop.
```

Kubernetes is like a production operations manager:

```text
Keep the system alive, scaled, networked, updated, and recoverable across a cluster.
```

The short version:

```text
Compose runs a group of containers.
Kubernetes operates a distributed application platform.
```


