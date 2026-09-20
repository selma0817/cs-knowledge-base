---
title: AWS VPC Networking
aliases:
  - VPC Networking
  - AWS Security Group
  - Public Subnet
  - Private Subnet
  - NAT Gateway
  - Internet Gateway
tags:
  - networking
  - aws
  - vpc
  - cloud
  - devops
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# AWS VPC Networking

AWS VPC networking is about controlling which resources can reach each other and which resources can reach or be reached from the public internet.

## VPC

A VPC is a private virtual network in AWS.

It is similar to a large configurable private LAN for cloud resources.

## Public vs private subnet

A subnet is public or private mostly because of its route table, not simply because of its IP range.

A public subnet usually has:

```text
0.0.0.0/0 -> Internet Gateway
```

A private subnet usually does not have a direct route to an Internet Gateway. It may use a NAT Gateway for outbound internet access:

```text
0.0.0.0/0 -> NAT Gateway
```

## Public subnet

A public subnet can route directly to and from the internet through an Internet Gateway.

For an EC2 instance to be reachable from the internet, it usually needs:

- public IPv4 or Elastic IP
- subnet route to Internet Gateway
- security group allowing inbound traffic
- network ACL allowing traffic
- app listening on the right interface and port
- OS firewall allowing traffic

## Private subnet

A private subnet is commonly used for app servers, databases, and internal services.

A common architecture:

```text
Internet
  -> Load Balancer in public subnet
  -> App servers in private subnet
  -> Database in private subnet
```

## Security group

A security group is a cloud-level virtual firewall attached to an EC2 instance or network interface.

It is:

- cloud-managed
- stateful
- allow-rule based
- outside the VM operating system

Example rules:

```text
Allow inbound TCP 22 from my IP
Allow inbound TCP 443 from 0.0.0.0/0
Allow inbound TCP 8080 from load balancer security group
```

## Security group vs OS firewall

Traffic may pass through:

```text
AWS route table / NACL
  -> Security Group
  -> EC2 network interface
  -> OS firewall: ufw / iptables
  -> Application process
```

A security group is outside the VM. An OS firewall runs inside the VM.

Both must allow traffic before the application is reachable.

## Network ACL

A Network ACL is subnet-level and stateless.

Simplified comparison:

```text
Security Group:
  instance/network-interface level
  stateful

Network ACL:
  subnet level
  stateless

OS firewall:
  inside the VM
```

## EC2 timeout example

Problem:

```bash
# On EC2
curl localhost:8080
# works

# From laptop
curl http://<public-ip>:8080
# times out
```

Likely causes:

1. Security group blocks inbound TCP 8080.
2. App listens only on `127.0.0.1:8080`.
3. OS firewall blocks 8080.
4. Docker port is not published.
5. Subnet route table is not public.
6. Network ACL blocks traffic.
7. Wrong public IP.

See [[Network Debugging Ladder]].

## Related

- [[Private IP Public IP and NAT]]
- [[Routing Default Gateway and Subnet]]
- [[Load Balancer]]
- [[Network Debugging Tools]]
- [[Kubernetes Service Networking]]
