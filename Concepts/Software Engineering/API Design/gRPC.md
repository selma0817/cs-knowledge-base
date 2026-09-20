---
date: 2026-06-27
tags:
  - grpc
  - api-design
  - microservice
  - protobuf
  - networking
topic: api-design
---
## One-sentence meaning

gRPC is a remote procedure call framework that lets one service call methods on another service over the network using a strongly defined service contract, commonly written in `.proto` files and serialized with Protocol Buffers.

## Why it matters

gRPC is useful in microservice systems because services often need to communicate frequently with each other. Compared with hand-written REST/JSON calls, gRPC gives services a shared schema, generated client/server code, compact binary messages, and support for streaming communication.

## Mental model

With REST, I usually think:

> Construct an HTTP request → send JSON → parse JSON response.

With gRPC, I think:

> Define a service method in `.proto` → generate client/server code → call the remote service method almost like a local function.

The function is not actually local, because it still crosses the network. But the generated client stub hides much of the manual HTTP request construction.

## Problems gRPC solves

### 1. Stronger service contract

A `.proto` file defines:

- service names
    
- method names
    
- request message types
    
- response message types
    
- field names and field numbers
    
- streaming behavior
    

This means both client and server agree on the API shape before runtime.

### 2. Generated code

Instead of manually writing request/response parsing logic, developers generate code from the `.proto` file.

In Go, this usually produces:

- Go structs for protobuf messages
    
- client code for calling the remote service
    
- server interfaces to implement
    
- registration functions for exposing the service
    
- stream helper types for streaming RPCs
    

### 3. More compact payloads than JSON

Protocol Buffers encode structured data into a compact binary format. This is usually smaller than JSON because it does not repeatedly include text field names in the payload.

Important correction: gRPC does not eliminate serialization/deserialization. It still serializes and deserializes data, but it does so using protobuf instead of text-based JSON.

### 4. Better fit for internal service-to-service communication

In many microservice systems, external clients call a public REST API, while internal services communicate with each other using gRPC.

Example:

```text
Browser / Mobile Client
        ↓ REST/JSON
API Gateway
        ↓ gRPC
User Service
        ↓ gRPC
Order Service
        ↓ gRPC
Payment Service
```

## `.proto` file

The `.proto` file is the API contract.

Example:

```proto
syntax = "proto3";

package user;

service UserService {
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
}

message GetUserRequest {
  string user_id = 1;
}

message GetUserResponse {
  string user_id = 1;
  string name = 2;
  string email = 3;
}
```

In this example:

- `UserService` is the service.
    
- `GetUser` is the remote method.
    
- `GetUserRequest` is the request message.
    
- `GetUserResponse` is the response message.
    
- field numbers like `1`, `2`, and `3` are part of the protobuf wire format.
    

## Protocol Buffers

Protocol Buffers, or protobuf, are a schema-based binary serialization format.

Compared with JSON:

|Aspect|JSON|Protobuf|
|---|---|---|
|Format|Text|Binary|
|Human-readable|Yes|Not directly|
|Schema|Optional / external|Built in through `.proto`|
|Payload size|Usually larger|Usually smaller|
|Type safety|Often runtime-level|Better compile-time support through generated code|
|Browser friendliness|Very good|Less direct|

## HTTP/2 and gRPC

gRPC commonly runs on HTTP/2.

HTTP/2 matters because it supports:

- long-lived connections
    
- multiplexing multiple streams over one connection
    
- bidirectional streaming
    
- flow control
    
- headers and trailers
    

My current understanding:

- HTTP/1.1 often maps one request-response flow more directly onto a connection.
    
- HTTP/2 allows multiple logical streams to share the same underlying TCP connection.
    
- This makes gRPC streaming and many concurrent RPCs more practical.
    

## Four gRPC communication patterns

### 1. Unary RPC

One request, one response.

```proto
rpc GetUser(GetUserRequest) returns (GetUserResponse);
```

This is closest to a normal REST request or a normal function call.

Use case:

- get user by ID
    
- create a record
    
- check status
    

### 2. Server streaming RPC

One request, many responses.

```proto
rpc ListOrders(ListOrdersRequest) returns (stream Order);
```

Use case:

- server sends many records
    
- live status updates
    
- logs or event feed
    

### 3. Client streaming RPC

Many requests, one response.

```proto
rpc UploadChunks(stream UploadChunk) returns (UploadSummary);
```

Use case:

- file upload
    
- batch ingestion
    
- client sends chunks of data
    

### 4. Bidirectional streaming RPC

Many requests, many responses.

```proto
rpc Chat(stream ChatMessage) returns (stream ChatMessage);
```

Use case:

- chat
    
- realtime collaboration
    
- interactive data exchange
    
- long-running agent/service communication
    

## gRPC vs REST

### Choose gRPC when

- services are internal
    
- communication is frequent
    
- latency and payload size matter
    
- both sides are controlled by the same engineering team
    
- strong API contracts are useful
    
- streaming is needed
    
- generated clients are helpful
    

### Choose REST when

- API is public-facing
    
- browser compatibility matters
    
- human readability matters
    
- simple CRUD endpoints are enough
    
- debugging with curl/Postman is important
    
- third-party developers need an easy integration path
    

## Authentication vs TLS/mTLS

Authentication and transport security are related but different.

### API-level authentication

This answers:

> Who is making this request, and what are they allowed to do?

Examples:

- JWT
    
- API key
    
- OAuth token
    
- user/session identity
    
- service identity passed in metadata
    

In gRPC, API-level auth information is often sent as request metadata.

### TLS

TLS answers:

> Is the network connection encrypted and is the server who it claims to be?

TLS protects data in transit.

### mTLS

mTLS means mutual TLS.

It answers:

> Can both client and server prove their identities using certificates?

mTLS is common in internal service-to-service systems because the server verifies the client service, not just the other way around.

## How gRPC fits into microservices

A common architecture:

```text
External Client
    ↓ REST/JSON
API Gateway
    ↓ gRPC
Internal Microservices
```

The external API may remain REST because it is easier for browsers, mobile apps, and third-party clients.

Internal services may use gRPC because they benefit from:

- generated clients
    
- faster binary serialization
    
- shared service contracts
    
- streaming
    
- better service-to-service structure
    

## Common pitfalls

### 1. Thinking gRPC removes network cost

gRPC makes remote calls look like local function calls, but they are still network calls.

A gRPC call can still fail because of:

- timeout
    
- service unavailable
    
- network partition
    
- server overload
    
- incompatible versions
    
- authentication failure
    

### 2. Overusing gRPC for public APIs

gRPC is great for internal services, but REST is often easier for public APIs.

### 3. Forgetting API versioning

Changing `.proto` files carelessly can break clients.

Need to understand:

- field numbers
    
- backward compatibility
    
- deprecated fields
    
- adding vs removing fields
    

### 4. Confusing API authentication with TLS

JWT/API keys identify the caller at the application level.

TLS/mTLS protects and authenticates the transport connection.

## Go implementation mental model

A `.proto` file is not directly compiled by Go. It is first passed to `protoc`.

`protoc-gen-go` generates Go structs and protobuf serialization code for messages.

`protoc-gen-go-grpc` generates gRPC client and server interfaces for services.

Then normal `go build` compiles both the generated code and my handwritten code.

The generated server interface forces my service implementation to match the `.proto` contract. The generated client forces callers to use the correct request/response types.

This catches many API-shape mistakes at compile time, but network failures, version mismatch, auth failure, and business logic errors still happen at runtime.

## Security mental model

Transport security, such as TLS or mTLS, protects the connection. It encrypts traffic and can verify peer identity.

API-level authentication and authorization identify the caller and decide what that caller is allowed to do.

In gRPC, API credentials such as JWTs are often passed through metadata, while TLS/mTLS protects the underlying connection.

## Is `.proto` Go syntax?

No. `.proto` files use Protocol Buffers syntax, which is a language-neutral interface/schema definition language.

The `.proto` file defines messages and services. Then `protoc` plus language-specific plugins generate code for a target language such as Go, Java, Python, or TypeScript.

For Go, `protoc-gen-go` generates protobuf message code, and `protoc-gen-go-grpc` generates gRPC client/server code.

The `.proto` file defines the API contract. The Go implementation defines the actual business behavior.

## Is `.proto` like SQL?

`.proto` is conceptually similar to SQL in the sense that both are domain-specific languages. SQL describes and queries relational database structures. `.proto` describes structured messages and service contracts for serialization and RPC.

`.proto` is not Go syntax. It is a language-neutral interface/schema definition language.

## Can I skip `.proto` and write Go structs directly?

For standard gRPC, no. A Go struct only describes the in-memory Go representation. gRPC/protobuf also needs field numbers, wire-format metadata, generated serialization code, generated client stubs, generated server interfaces, and service registration code.

The `.proto` file should be treated as the source of truth. `protoc` reads it and generates Go code. My handwritten Go code then implements the generated server interface.


## Related notes

- [[REST API]]
    
- [[Protocol Buffers]]
    
- [[HTTP2]]
    
- [[Service-to-Service Communication]]
    
- [[Microservices]]
    
- [[API Gateway]]
    
- [[Authentication]]
    
- [[JWT]]
    
- [[TLS]]
    
- [[mTLS]]
    
- [[Go gRPC]]
    
- [[Go Microservices - Shortly Clone]]