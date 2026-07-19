# LinkPulse

> A URL shortener + real-time analytics platform, built on Kubernetes with production patterns — GitOps, service mesh-ready, and observable.

This repo contains everything I built while learning production-grade Kubernetes locally on a Mac mini before moving to AWS EKS. It's a real working microservices application with 5 services, PostgreSQL, Redis, JWT auth, and GitOps deployment via ArgoCD.

**Repo:** [github.com/jasvithchand/gitops-demo](https://github.com/jasvithchand/gitops-demo)

---

## Table of Contents

1. [What This Project Is](#1-what-this-project-is)
2. [The Big Picture — How Everything Fits Together](#2-the-big-picture)
3. [The Stack — What Each Piece Does](#3-the-stack)
4. [Core Concepts — With Analogies](#4-core-concepts)
5. [Repo Structure](#5-repo-structure)
6. [Setup From Scratch — Full Steps](#6-setup-from-scratch)
7. [Testing the Full Flow](#7-testing-the-full-flow)
8. [Common Operations](#8-common-operations)
9. [Troubleshooting](#9-troubleshooting)
10. [What's Next — Roadmap to AWS](#10-whats-next)

---

## 1. What This Project Is

LinkPulse is a URL shortener. You give it `https://very-long-url.com/blah/blah` and it gives you back `linkpulse.io/abc123`. When someone clicks that short link, they get redirected to the original URL.

Simple concept — but the internals are structured like a real production system:

- **5 microservices** talking to each other over HTTP
- **JWT authentication** with RSA-signed tokens
- **Redis cache** for sub-millisecond redirect lookups
- **PostgreSQL** as the source of truth for users and links
- **GitOps** — every deployment is a `git push`
- **Ingress** — real URL routing, not just port-forward hacks
- **Observability** — Prometheus scrapes metrics from every service

Everything runs on a local Kubernetes cluster (Docker Desktop) but is designed to move to AWS EKS with only configuration changes — no code changes.

---

## 2. The Big Picture

Here's a request flowing through the system when someone clicks a short link:

```
                    ┌─────────────────────────────────┐
                    │            YOUR MAC              │
                    │  browser: http://nginx.local     │
                    └────────────────┬────────────────┘
                                     │
                                     │ /etc/hosts: nginx.local → 127.0.0.1
                                     ▼
    ┌────────────────────────────────────────────────────────────────┐
    │                     DOCKER DESKTOP VM                           │
    │   (a hidden Linux VM running your entire cluster)               │
    │                                                                 │
    │   ┌──────────────────────────────────────────────────────────┐  │
    │   │              KUBERNETES CLUSTER                          │  │
    │   │                                                          │  │
    │   │   ┌────────────────────────────────────────────────────┐ │  │
    │   │   │   ingress-nginx namespace                          │ │  │
    │   │   │   NGINX Ingress Controller (listens :80)           │ │  │
    │   │   │   → routes based on host + path                    │ │  │
    │   │   └───────────────┬────────────────────────────────────┘ │  │
    │   │                   │                                       │  │
    │   │                   ▼                                       │  │
    │   │   ┌────────────────────────────────────────────────────┐ │  │
    │   │   │   services namespace                               │ │  │
    │   │   │                                                    │ │  │
    │   │   │   ┌──────────┐   ┌─────────────┐  ┌────────────┐   │ │  │
    │   │   │   │auth-svc  │   │shortener-svc│  │redirect-svc│   │ │  │
    │   │   │   │  :3001   │←──│    :3002    │  │   :3003    │   │ │  │
    │   │   │   │  JWT     │   │  writes to  │  │ reads from │   │ │  │
    │   │   │   │  signer  │   │  Redis      │  │ Redis      │   │ │  │
    │   │   │   └──────────┘   └──────┬──────┘  └─────┬──────┘   │ │  │
    │   │   │                         │                │           │ │  │
    │   │   │   ┌────────────┐        │                │           │ │  │
    │   │   │   │dashboard-  │        │                │           │ │  │
    │   │   │   │service     │        │                │           │ │  │
    │   │   │   │  :3000     │        │                │           │ │  │
    │   │   │   │(static UI) │        │                │           │ │  │
    │   │   │   └────────────┘        │                │           │ │  │
    │   │   │                         │                │           │ │  │
    │   │   │   ┌────────────┐        │                │           │ │  │
    │   │   │   │analytics-  │        │                │           │ │  │
    │   │   │   │service     │        │                │           │ │  │
    │   │   │   │  :3004     │        │                │           │ │  │
    │   │   │   │(Python)    │        │                │           │ │  │
    │   │   │   └────────────┘        │                │           │ │  │
    │   │   └─────────────────────────┼────────────────┼──────────┘ │  │
    │   │                             ▼                ▼             │  │
    │   │   ┌──────────────────────────────────────────────────────┐ │  │
    │   │   │   data namespace                                     │ │  │
    │   │   │   ┌──────────────┐        ┌─────────────┐            │ │  │
    │   │   │   │postgres-0    │        │redis-0      │            │ │  │
    │   │   │   │StatefulSet   │        │StatefulSet  │            │ │  │
    │   │   │   │+ 1Gi PVC     │        │+ 512Mi PVC  │            │ │  │
    │   │   │   └──────────────┘        └─────────────┘            │ │  │
    │   │   └──────────────────────────────────────────────────────┘ │  │
    │   │                                                             │  │
    │   │   ┌──────────────────────────────────────────────────────┐ │  │
    │   │   │   argocd namespace                                   │ │  │
    │   │   │   watches github.com/jasvithchand/gitops-demo        │ │  │
    │   │   │   syncs any change to the cluster automatically      │ │  │
    │   │   └──────────────────────────────────────────────────────┘ │  │
    │   │                                                             │  │
    │   │   ┌──────────────────────────────────────────────────────┐ │  │
    │   │   │   monitoring namespace                               │ │  │
    │   │   │   Prometheus scrapes /metrics from every service     │ │  │
    │   │   │   Grafana dashboards for visualization               │ │  │
    │   │   └──────────────────────────────────────────────────────┘ │  │
    │   │                                                             │  │
    │   │   ┌──────────────────────────────────────────────────────┐ │  │
    │   │   │   kube-system                                        │ │  │
    │   │   │   Control plane + sealed-secrets-controller          │ │  │
    │   │   │   (decrypts SealedSecrets from Git into real Secrets)│ │  │
    │   │   └──────────────────────────────────────────────────────┘ │  │
    │   └─────────────────────────────────────────────────────────────┘  │
    └─────────────────────────────────────────────────────────────────────┘
```

### Full request flow — clicking a short link

```
1.  Browser: GET http://linkpulse.io/abc123
2.  /etc/hosts resolves → 127.0.0.1
3.  Hits NGINX Ingress Controller pod on :80
4.  Ingress rule matches host → routes to redirect-service ClusterIP
5.  kube-proxy iptables DNAT → rewrites destination to a redirect-service pod IP
6.  redirect-service reads Redis: GET link:abc123
7.  Returns HTTP 302 with Location: https://original-long-url.com
8.  Browser follows redirect to the original URL
```

---

## 3. The Stack

### Services (the microservices you'd build)

| Service | Port | Language | Job |
|---|---|---|---|
| `auth-service` | 3001 | Node.js 20 | Signs JWTs on login, validates them on request |
| `shortener-service` | 3002 | Node.js 20 | Creates short codes, writes to Redis (calls auth-service to validate JWT first) |
| `redirect-service` | 3003 | Node.js 20 | The hot path — reads Redis, returns HTTP 302 redirect |
| `analytics-service` | 3004 | Python 3.12 | Async event consumer stub (RabbitMQ/SQS coming later) |
| `dashboard-service` | 3000 | nginx | Serves the static HTML frontend |

### Infrastructure (what your services need to run)

| Component | Purpose |
|---|---|
| **PostgreSQL 16 (StatefulSet)** | Source of truth for users, links, analytics |
| **Redis 7.2 (StatefulSet)** | Cache for short code lookups — sub-millisecond reads |
| **NGINX Ingress Controller** | Routes external traffic to services |
| **ArgoCD** | GitOps engine — syncs cluster to match Git |
| **Sealed Secrets** | Encrypts secrets so they're safe in Git |
| **Prometheus + Grafana** | Metrics scraping + dashboards |

### Platform (Kubernetes itself)

| Component | Purpose |
|---|---|
| **Docker Desktop Kubernetes** | Local single-node cluster (kubeadm v1.34.1) |
| **CoreDNS** | Resolves service names to ClusterIPs |
| **kube-proxy** | Programs iptables for ClusterIP routing |
| **containerd** | Container runtime — actually starts your containers |
| **etcd** | The cluster's database — every object lives here |

---

## 4. Core Concepts

### Kubernetes as a whole

**Analogy: an ant colony.**

Every ant follows simple rules. No ant is in charge. The queen (control plane) lays down what needs to exist (pods, services, etc.), and thousands of worker ants (kubelet, kube-proxy, controllers) constantly compare "what should exist" vs "what does exist" and fix any differences. If you kill an ant, another takes its place. If you kill a pod, another one starts.

The key insight: **nothing is imperative in Kubernetes.** You never say "start a pod." You say "there should be a pod matching this spec" and Kubernetes' reconciliation loops make it true and keep it true.

---

### etcd — the cluster database

**Analogy: the mission control whiteboard.**

Every satellite, every astronaut, every fuel level, every orbit — written on the whiteboard. Every controller in mission control watches the whiteboard. When something changes, whoever's responsible for that thing reacts.

etcd is that whiteboard. Every pod spec, secret, config, and service lives there as a key like `/registry/pods/default/my-pod`. When you run `kubectl apply`, all it does is update the whiteboard. Every other component watches for changes and reacts.

**You saw this live** when you ran `etcdctl watch` and created a pod — 4 PUT events fired, one for each stage: created → scheduled → creating → running. Each event was a different component updating the whiteboard.

---

### Namespaces

**Analogy: apartments in a building.**

Same building (cluster), separate apartments. What's in apartment 3B is invisible to apartment 5A unless they explicitly share. Names can repeat across apartments — every apartment can have its own "living room."

This project uses:
- `services` — your microservices
- `data` — databases (PostgreSQL, Redis)
- `argocd` — the GitOps engine
- `monitoring` — Prometheus + Grafana
- `ingress-nginx` — the ingress controller
- `kube-system` — Kubernetes itself

Cross-namespace DNS lookups use the full name: `redis-0.redis.data.svc.cluster.local` — that's `pod.service.namespace.svc.cluster.local`.

---

### Pods vs Deployments vs StatefulSets

**Analogy:**
- **Pod** = a single employee
- **Deployment** = a temp agency that always keeps N interchangeable employees on the job — if one quits, another shows up. Nobody's name matters, they're all "the temp."
- **StatefulSet** = a department with named roles (CEO, CFO, CTO). Each role has its own office (PVC) and business cards (DNS name). If the CEO leaves, the replacement gets the same office and same title.

Regular apps → Deployment. Databases → StatefulSet. Never mix them up — running PostgreSQL as a Deployment will corrupt your data the first time a pod restarts on a different node.

---

### Services (ClusterIP)

**Analogy: a corporate switchboard.**

You don't call your friend's desk phone directly — you call the switchboard and ask for them by name. Even if they moved to a different floor, you still reach them.

A Service gives your pods a stable virtual IP (VIP) and DNS name. Pods die and get recreated with different IPs — Services stay put. Requests to the Service get load-balanced across all matching pods.

**The magic**: ClusterIPs don't exist on any real machine. They're purely `iptables` rules that kube-proxy writes on every node. When a pod sends a packet to 10.96.45.12, the kernel intercepts it, picks a target pod, and rewrites the destination — all in the network stack, before the packet leaves.

---

### Headless Services

**Analogy: a company directory instead of a switchboard.**

For databases you don't want load balancing — you want to talk to a specific pod. `postgres-0` is your primary, you write to it. `postgres-1` might be a replica.

A headless service (`clusterIP: None`) gives you direct DNS records per pod instead of a shared VIP:
- `postgres-0.postgres.data.svc.cluster.local` → pod IP directly
- No iptables tricks, no load balancing

Used for StatefulSets where each pod has a distinct identity.

---

### Port-Forwarding

**Analogy: a temporary phone line into a secure office.**

Imagine a building where every phone is internal-only — you can't dial in from outside. Now security patches a phone line from a jack in the lobby (`localhost:8080`) all the way to a specific desk inside (`pod:3002`). While you're on the line, you can talk to that desk. Hang up, and the line is gone. No record it ever existed.

Port-forward:
- Opens a socket on your Mac (127.0.0.1:XXXX)
- Tunnels through the Kubernetes API server via websocket
- To a specific pod's port
- Dies the moment you hit Ctrl+C

**It's a debugging tool.** Nothing is created in the cluster. In production you use Ingress (a real front door), not port-forward.

---

### Ingress vs Service vs Port-Forward — the three ways in

| Method | What it is | Persistence | Use case |
|---|---|---|---|
| **Port-forward** | Temporary tunnel through API server | Dies with terminal | Debugging |
| **Service (LoadBalancer)** | Real cloud load balancer per service | Permanent | Individual public endpoint |
| **Ingress** | One load balancer routing to many services | Permanent | Production external traffic |

---

### JWT — JSON Web Tokens

**Analogy: a signed concert ticket.**

The venue signs your ticket with their private stamp. When you show up, any bouncer at any door can look at the stamp and verify it's real — they don't need to call the ticket office. They can read your seat number off the ticket. But nobody can forge a new ticket without the venue's stamp.

A JWT has 3 parts: `header.payload.signature`

- **Header**: "this token was signed with RS256"
- **Payload**: `{ userId: 42, email: "you@example.com", exp: <one hour from now> }`
- **Signature**: RSA-encrypted hash of header + payload, signed with auth-service's private key

Any service with auth-service's **public** key can verify the signature — no network call to auth-service needed on every request. This is why JWTs scale.

**The security property**: forging a valid signature requires the private key. Anyone can read the payload — it's base64, not encrypted. So never put secrets in a JWT.

**In this project:**
- `auth-service` holds the private key (from a SealedSecret)
- Signs tokens on `POST /login` with expiry 1 hour
- `shortener-service` calls `auth-service` to validate tokens (later Kong will do this at the edge)

---

### TLS Certificates vs JWT — different problems

**TLS certificates** answer: "am I actually talking to who I think I'm talking to, and is the connection encrypted?" Machine-to-machine trust.

**JWT tokens** answer: "is this request coming from an authenticated user with permission?" User-to-app trust.

You need both. HTTPS to encrypt the wire, JWT to authenticate the user inside.

---

### Sealed Secrets

**Analogy: a wall safe that only your cluster can open.**

Regular Kubernetes Secrets are just base64-encoded — anyone with cluster access can read them. That's fine at runtime but you can't commit them to Git — they're not actually encrypted.

Sealed Secrets solve this with a wall safe metaphor:
1. The cluster has a private key locked inside the `sealed-secrets-controller`
2. `kubeseal` CLI on your Mac uses the public half to encrypt secrets
3. The resulting `SealedSecret` YAML is useless without the cluster's private key
4. **Safe to commit to Git** — even if your repo is public, the sealed secrets stay locked
5. When ArgoCD applies the SealedSecret to the cluster, the controller decrypts it into a real Secret
6. Your pod reads the real Secret normally

**In this project**: PostgreSQL password and JWT signing keys are stored as SealedSecrets in Git.

---

### Helm

**Analogy: a resume template.**

Same résumé skeleton — you fill in your name, job history, skills. The template stays the same across everyone who uses it.

Helm charts are templates for Kubernetes YAML. The template file has placeholders like `{{ .Values.replicaCount }}`. You put actual values in `values.yaml`. Helm renders the template + values into finished YAML and applies it.

**Why this matters**: you change one line in `values.yaml`, push to Git, and ArgoCD updates the entire deployment. No hand-editing 400-line YAML files.

---

### ArgoCD — GitOps

**Analogy: a thermostat.**

You set the temperature you want (Git). The thermostat (ArgoCD) constantly compares "current temperature" (cluster state) to "target temperature" (Git). If they differ, it kicks the HVAC on.

You never manually change cluster state — you change Git and ArgoCD reconciles.

**The loop:**
```
you edit values.yaml → git push
  → ArgoCD detects diff (every 3 min or on webhook)
  → renders Helm chart with new values
  → applies to cluster
  → cluster matches Git
```

**selfHeal** means if someone manually changes cluster state (`kubectl edit`), ArgoCD reverts it back to Git within minutes. Git is the ONLY source of truth.

---

### Prometheus

**Analogy: a health inspector doing rounds.**

Every 15 seconds Prometheus visits every pod that exposes `/metrics` and reads a page of numbers: request count, memory usage, error count. Stores them all as time series. When you query it, you can ask "what was request rate 5 minutes ago" or "when did errors spike."

Grafana is the wall of monitors visualizing all this data.

---

### The Docker Desktop VM

**Analogy: a Russian nesting doll.**

Your Mac (macOS) can't run Linux containers natively. Docker Desktop hides a Linux VM inside itself. Your entire "Kubernetes cluster" — every pod, every container — actually runs inside that hidden Linux VM. When you `kubectl get nodes` and see "docker-desktop", that's the VM.

This is why when you close Docker Desktop the whole cluster pauses but doesn't lose data — the VM state is preserved on your Mac's disk.

---

## 5. Repo Structure

```
gitops-demo/
├── README.md                        ← this file
├── cluster.sh                       ← manage the local cluster (down/up/status)
│
├── argocd-app.yaml                  ← ArgoCD Application for nginx-app (legacy demo)
├── argocd-apps/                     ← one ArgoCD Application per chart
│   ├── postgres-app.yaml
│   ├── redis-app.yaml
│   ├── auth-service-app.yaml
│   ├── shortener-service-app.yaml
│   ├── redirect-service-app.yaml
│   ├── analytics-service-app.yaml
│   └── dashboard-service-app.yaml
│
├── infra/                           ← stateful infrastructure
│   ├── postgres/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── statefulset.yaml
│   │       ├── service.yaml         ← headless service
│   │       └── sealed-secret.yaml   ← encrypted DB password
│   └── redis/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── statefulset.yaml
│           └── service.yaml
│
├── services/                        ← the microservices
│   ├── auth-service/
│   │   ├── app/                     ← application code + Dockerfile
│   │   │   ├── index.js
│   │   │   ├── package.json
│   │   │   └── Dockerfile
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── sealed-secret.yaml   ← JWT signing keys, encrypted
│   ├── shortener-service/
│   ├── redirect-service/
│   ├── analytics-service/
│   ├── dashboard-service/
│   └── build.sh                     ← build + push all service images to ghcr.io
│
└── nginx-app/                       ← original GitOps demo (nginx + ConfigMap)
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── deployment.yaml
        ├── service.yaml
        ├── configmap.yaml
        └── ingress.yaml
```

---

## 6. Setup From Scratch

Full step-by-step to rebuild everything.

### Prerequisites

- macOS with Docker Desktop
- 10GB+ RAM allocated to Docker Desktop
- `kubectl`, `helm`, `argocd`, `kubeseal`, `docker` CLIs installed via Homebrew
- GitHub account with a Personal Access Token (`write:packages` scope)

### Step 1 — Enable Kubernetes

1. Docker Desktop → Settings → Kubernetes → Enable Kubernetes
2. Settings → Resources → Memory: 10GB
3. Apply & Restart
4. Verify:
   ```bash
   kubectl get nodes
   # docker-desktop   Ready   control-plane   ...
   ```

### Step 2 — Install cluster prerequisites

```bash
# ArgoCD — GitOps engine
kubectl create namespace argocd
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Sealed Secrets — encrypts secrets safely in Git
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set fullnameOverride=sealed-secrets-controller

# NGINX Ingress Controller — routes external traffic
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer

# Prometheus + Grafana — observability
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=admin123 \
  --set alertmanager.enabled=false \
  --set nodeExporter.enabled=false
```

### Step 3 — Bootstrap ArgoCD

```bash
# Get the auto-generated admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward the UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080  (accept cert warning)

# Login via CLI
argocd login localhost:8080 --username admin --insecure
```

### Step 4 — Login to GitHub Container Registry

```bash
echo "YOUR_GITHUB_TOKEN" | docker login ghcr.io \
  -u jasvithchand --password-stdin
```

### Step 5 — Deploy PostgreSQL + Redis

```bash
# Create the namespace
kubectl create namespace data

# Point ArgoCD at postgres and redis
kubectl apply -f argocd-apps/postgres-app.yaml
kubectl apply -f argocd-apps/redis-app.yaml

# Watch them come up
kubectl get pods -n data -w
# Wait until both show 1/1 Running
```

### Step 6 — Build and push service images

```bash
# One-time: create the services namespace
kubectl create namespace services

# Build all 4 Node.js/Python service images and push to ghcr.io
./services/build.sh

# ⚠️ Make each ghcr.io package public:
# github.com/jasvithchand?tab=packages
# → click each package → Package settings → Change visibility → Public
```

### Step 7 — Deploy services

```bash
# Apply all 5 ArgoCD Applications
for app in argocd-apps/*.yaml; do kubectl apply -f "$app"; done

# Watch everything come up
kubectl get pods -n services -w
# Wait for 5/5 Running
```

### Step 8 — Verify

```bash
kubectl get pods -n services
# All 5 should be 1/1 Running
```

Move to section 7 to test the full flow.

---

## 7. Testing the Full Flow

This proves inter-service communication actually works.

### Set up port-forwards (each in its own terminal)

```bash
# Terminal 1
kubectl port-forward svc/auth-service 3001:3001 -n services

# Terminal 2
kubectl port-forward svc/shortener-service 3002:3002 -n services

# Terminal 3
kubectl port-forward svc/redirect-service 3003:3003 -n services

# Terminal 4
kubectl port-forward svc/dashboard-service 3000:3000 -n services
```

### Test in a 5th terminal

```bash
# 1. Login and grab JWT
JWT=$(curl -s -X POST http://localhost:3001/login \
  -H "Content-Type: application/json" \
  -d '{"email":"jasvith@linkpulse.io","password":"password123"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

echo "JWT captured: ${JWT:0:50}..."

# 2. Create a short link (proves shortener-service → auth-service → Redis works)
curl -s -X POST http://localhost:3002/links \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d '{"url":"https://github.com/jasvithchand/gitops-demo"}' \
  | python3 -m json.tool

# 3. Test the redirect (proves redirect-service → Redis works)
# Copy the "code" value from step 2, then:
curl -sI http://localhost:3003/YOUR_CODE_HERE
# Should see: HTTP/1.1 302 Found
#             Location: https://github.com/jasvithchand/gitops-demo

# 4. Open the dashboard
open http://localhost:3000
```

### What the full flow proves

- **Login** → auth-service signed a JWT with RSA private key
- **Create link** → shortener-service called auth-service via ClusterIP DNS to validate JWT, then wrote to Redis
- **Redirect** → redirect-service read from Redis and returned HTTP 302
- All service-to-service traffic went through **CoreDNS → ClusterIP VIP → iptables DNAT → pod IP**
- Redis data survived cluster restarts because of the **PVC**

---

## 8. Common Operations

### Cool down your Mac

Just close Docker Desktop. The VM suspends — all pods pause without losing data. Reopen it later and everything resumes exactly where it left off.

### Update a service

```bash
# Edit code
vim services/shortener-service/app/index.js

# Rebuild + push image
docker build -t ghcr.io/jasvithchand/shortener-service:latest \
  services/shortener-service/app
docker push ghcr.io/jasvithchand/shortener-service:latest

# Force pods to pull the new image
kubectl rollout restart deployment shortener-service -n services

# Commit code
git add . && git commit -m "update shortener" && git push
```

### Scale a service

```bash
# Edit services/shortener-service/values.yaml
# Change replicaCount: 1  →  replicaCount: 3

git add . && git commit -m "scale shortener" && git push
# ArgoCD syncs automatically within 3 min
```

### Update a secret

```bash
# 1. Get the cluster's public key
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  > /tmp/pub-cert.pem

# 2. Create the new secret + seal it
kubectl create secret generic my-secret \
  --namespace=services \
  --from-literal=API_KEY=newvalue \
  --dry-run=client -o yaml \
  | kubeseal --cert /tmp/pub-cert.pem --format yaml \
  > services/my-service/templates/sealed-secret.yaml

# 3. Push
git add . && git commit -m "rotate api key" && git push
```

### Access observability

```bash
# Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# http://localhost:3000  →  admin / admin123

# Prometheus
kubectl port-forward -n monitoring \
  svc/prometheus-kube-prometheus-prometheus 9090:9090
# http://localhost:9090
```

### View service logs

```bash
# Live logs from one service
kubectl logs -n services -l app=shortener-service -f

# Last 50 lines from a specific pod
kubectl logs -n services shortener-service-abc123 --tail=50

# Previous container's logs (if crashed)
kubectl logs -n services shortener-service-abc123 --previous
```

### Shell into a running pod

```bash
kubectl exec -it -n services deploy/shortener-service -- sh

# Query Redis directly
kubectl exec -it -n data redis-0 -- redis-cli
> KEYS link:*
> GET link:abc123

# Query PostgreSQL directly
kubectl exec -it -n data postgres-0 -- \
  psql -U linkpulse -d linkpulse
```

---

## 9. Troubleshooting

### Pod stuck `Pending`

Usually a PVC not binding. Check:

```bash
kubectl describe pod POD_NAME -n NAMESPACE | grep -A5 Events
kubectl get pvc -n NAMESPACE
kubectl describe pvc PVC_NAME -n NAMESPACE
```

Common fix: PVC has empty `storageClassName`. Change to `"hostpath"` in `values.yaml`, then delete the stuck PVC so StatefulSet recreates it.

### `ImagePullBackOff`

Image doesn't exist on ghcr.io, or ghcr.io package is private.

```bash
# See exact error
kubectl describe pod POD_NAME -n services | grep -A5 Events
```

- **"unauthorized"** → make packages public at github.com/jasvithchand?tab=packages
- **"not found"** → run `./services/build.sh` to push

### Pod restarts constantly with `Error` exit code

Node.js app is crashing or missing `app.listen()`. Get logs:

```bash
kubectl logs -n services POD_NAME --previous
```

Common bug: `app.listen()` binds to `127.0.0.1` instead of `0.0.0.0` — health probes fail. Fix in code:

```js
app.listen(PORT, '0.0.0.0', () => { ... });
```

### `OOMKilled` (exit code 137)

Container hit its memory limit. Increase in `values.yaml`:

```yaml
resources:
  limits:
    memory: 256Mi   # bump up from 128Mi
```

Then push — ArgoCD syncs, pods restart with new limits.

### ArgoCD session expired

```bash
# Re-login
argocd login localhost:8080 --username admin --insecure
```

### `kubectl` returns `couldn't get current server API group list`

The Kubernetes API server isn't running. Restart Docker Desktop — the whole cluster came back for me because Docker Desktop preserves the VM state on disk.

---

## 10. What's Next

### Phase 3 — Security

- **RBAC** — ServiceAccounts with least-privilege permissions per service
- **NetworkPolicy** — redirect-service can only reach Redis, not PostgreSQL
- **Pod Security Standards** — enforce non-root, read-only filesystem etc.

### Phase 4 — Kong API Gateway

- DB-less Kong deployed via Helm
- JWT validation at the edge (services stop calling auth-service on every request)
- Rate limiting (100 req/s per user)
- All external traffic routes through Kong

### Phase 5 — Istio Service Mesh

- Sidecar injection into every pod (Envoy)
- Automatic mTLS between all services
- Traffic policies (circuit breakers, retries, timeouts)
- Distributed tracing spans automatically populated

### Phase 6 — Event-driven with RabbitMQ

- redirect-service publishes click events to RabbitMQ
- analytics-service consumes them asynchronously
- notification-service consumes for milestone alerts
- Pattern maps 1:1 to AWS SQS

### Phase 7 — Jaeger Distributed Tracing

- Full trace: Kong → shortener-service → auth-service → Redis
- Span timing, error propagation

### Phase 8 — Load Testing with k6

- Hammer redirect-service with 1000 req/s
- Watch HPA scale pods 2 → 10 in real time
- Watch Redis cache hit rate in Grafana

### Phase 9 — Move to AWS EKS

- Terraform for VPC + EKS + RDS + ElastiCache + MSK
- AWS Load Balancer Controller (replaces NGINX Ingress with ALB)
- ECR instead of ghcr.io
- IRSA — IAM Roles for Service Accounts
- Cost target: $40-80/month with stop-start strategy

---

## Credits

Built while learning Kubernetes deeply — from etcd internals to real microservices — before moving to AWS EKS. Every layer here (SealedSecrets, StatefulSets with PVCs, GitOps via ArgoCD, JWT auth) is a pattern used in production.

**Author:** Jasvith Chandanne — Software Engineer at Apple
**Repo:** [github.com/jasvithchand/gitops-demo](https://github.com/jasvithchand/gitops-demo)