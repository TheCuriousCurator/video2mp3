# Minikube Tunnel Issue - Solution Summary

## Initial Problem
- Ran `minikube tunnel` but saw `services: []` (no services being tunneled)
- Wanted to access RabbitMQ at `rabbitmq-manager.com`

## Root Cause Analysis

### Step 1: Check Services
```bash
kubectl get services --all-namespaces
```
**Finding:** All services were **ClusterIP** or **NodePort** type
**Problem:** `minikube tunnel` only works with **LoadBalancer** services
**Result:** No LoadBalancer services = empty tunnel

### Step 2: Check Ingress Resources
```bash
kubectl get ingress --all-namespaces
```
**Finding:** Ingress configured for `rabbitmq-manager.com` → `192.168.49.2`
**Meaning:** Using **Ingress** (not LoadBalancer) for routing

### Step 3: Check /etc/hosts File
```bash
grep -E "(video2mp3|rabbitmq-manager)" /etc/hosts
```
**Finding:** `127.0.0.1 rabbitmq-manager.com`
**Problem:** Hosts file pointed to localhost, but Ingress was at `192.168.49.2`
**Result:** Mismatch between /etc/hosts and Ingress address

## Solution Options

### Option 1: Update /etc/hosts to Minikube IP
```bash
sudo sed -i 's/127.0.0.1 rabbitmq-manager.com/192.168.49.2 rabbitmq-manager.com/' /etc/hosts
sudo sed -i 's/127.0.0.1 video2mp3.com/192.168.49.2 video2mp3.com/' /etc/hosts
```
**Best for:** Simulating production environment with Ingress

### Option 2: Use Port Forwarding (CHOSEN SOLUTION)

#### Setup Commands:

**RabbitMQ Management UI:**
```bash
kubectl port-forward pod/rabbitmq-0 15672:15672 > /tmp/rabbitmq-pf.log 2>&1 &
```
Access at: http://localhost:15672 or http://rabbitmq-manager.com:15672
Credentials: `guest` / `guest`

**Gateway:**
```bash
sudo kubectl port-forward service/gateway 80:8080 > /tmp/gateway-pf.log 2>&1 &
```
Access at: http://localhost/login or http://video2mp3.com/login (clean URLs!)

**Example login command:**
```bash
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login
```
Expected: Returns JWT token

**Note:** Port 80 requires sudo. If you prefer no sudo, use port 8080 instead and add `:8080` to URLs.

**Auth Service (optional - for direct access):**
```bash
kubectl port-forward service/auth 5000:5000 > /tmp/auth-pf.log 2>&1 &
```
Access at: http://localhost:5000

**Note:** For auth service issues (404 errors, MySQL connectivity), see [Auth Service Solution Guide](../auth/solution-auth-login.md)

#### Verify Port Forward is Working:
```bash
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:15672
```
Expected: HTTP Status: 200

#### Manage Port Forwards:

**View active port forwards:**
```bash
ps aux | grep "kubectl port-forward"
```

**Stop a specific port forward:**
```bash
pkill -f "kubectl port-forward pod/rabbitmq-0"
```

**Stop all port forwards:**
```bash
pkill -f "kubectl port-forward"
```

**Best for:** Quick local development without modifying system files

### Option 3: Use NodePort
Access services directly via NodePort without Ingress:
```bash
kubectl get svc rabbitmq
# Access at: http://192.168.49.2:<NodePort>
```
**Best for:** Direct access without Ingress

## How Port Forwarding Works

```
Browser Request                  Kubernetes Cluster
─────────────────                ──────────────────

rabbitmq-manager.com:15672
         ↓
/etc/hosts lookup
         ↓
127.0.0.1:15672
         ↓
kubectl port-forward (listening on localhost:15672)
         ↓
                              → Pod rabbitmq-0:15672
                                (RabbitMQ Management UI)
```

## Traffic Flow Explained

1. Browser requests `rabbitmq-manager.com:15672`
2. `/etc/hosts` resolves to `127.0.0.1`
3. `kubectl port-forward` listens on `localhost:15672`
4. Forwards traffic to `rabbitmq-0` pod on port `15672`
5. RabbitMQ Management UI responds

## Key Takeaways

- **minikube tunnel** is for LoadBalancer services only
- Project uses **Ingress** (nginx) for routing
- Port forwarding bypasses Ingress and creates a direct localhost tunnel to pods
- This matches the `/etc/hosts` setup pointing to `127.0.0.1`
- No need to run `minikube tunnel` when using Ingress + Port Forwarding

## Why Tunnel Showed Empty Services

The tunnel output showed `services: []` because:
1. `minikube tunnel` only exposes LoadBalancer type services
2. All project services are ClusterIP or NodePort
3. Ingress controller is NodePort (not LoadBalancer)
4. Therefore, tunnel had nothing to expose

## Complete Debugging Journey

### Initial Investigation: Why is Tunnel Empty?

**Command run:**
```bash
minikube tunnel
```

**Output:**
```
Status:
        machine: minikube
        pid: 12345
        route: 10.96.0.0/12 -> 192.168.49.2
        minikube: Running
        services: []
        errors: none
```

**Question:** Why `services: []`? Nothing is being tunneled!

### Step-by-Step Investigation

**1. What services exist?**
```bash
kubectl get services --all-namespaces
```
Output showed all services as **ClusterIP** or **NodePort** type.

**Key Learning:** `minikube tunnel` only works with **LoadBalancer** services!

**2. Do we have any LoadBalancer services?**
```bash
kubectl get services --all-namespaces -o wide | grep LoadBalancer
```
No output - no LoadBalancer services found.

**Conclusion:** That's why tunnel shows `services: []` - there's nothing for it to tunnel!

**3. How are we accessing services then?**
```bash
kubectl get ingress --all-namespaces
```
Found Ingress resources configured for `rabbitmq-manager.com` and `video2mp3.com`.

**Key Learning:** Project uses **Ingress** (nginx) for routing, not LoadBalancer services!

**4. Where does Ingress point to?**
```bash
kubectl get ingress rabbitmq-ingress -o yaml | grep -A 5 "host:"
```
Shows: `rabbitmq-manager.com` → `192.168.49.2` (minikube IP)

**5. Where does /etc/hosts point?**
```bash
grep -E "(video2mp3|rabbitmq-manager)" /etc/hosts
```
Output: `127.0.0.1 rabbitmq-manager.com` and `127.0.0.1 video2mp3.com`

**Problem Found!** Mismatch:
- `/etc/hosts`: Points domains to `127.0.0.1` (localhost)
- Ingress: Routes traffic at `192.168.49.2` (minikube IP)
- Result: Browser goes to localhost, but Ingress isn't there!

### Solutions Analysis

**Option A: Update /etc/hosts to minikube IP**
```bash
sudo sed -i 's/127.0.0.1 rabbitmq-manager.com/192.168.49.2 rabbitmq-manager.com/' /etc/hosts
```
- ✅ Simulates production Ingress routing
- ❌ Requires system file modification
- ❌ Breaks if minikube IP changes

**Option B: Port Forwarding (CHOSEN)**
```bash
kubectl port-forward service/gateway 80:8080 &
kubectl port-forward pod/rabbitmq-0 15672:15672 &
```
- ✅ Works with existing `/etc/hosts` (127.0.0.1)
- ✅ No system file changes
- ✅ Easy to start/stop
- ❌ Requires manually starting port forwards

**Why Port Forwarding Works:**
1. `/etc/hosts` resolves `video2mp3.com` → `127.0.0.1` ✅
2. `kubectl port-forward` listens on `127.0.0.1:80` ✅
3. Forwards directly to pod/service in cluster ✅
4. Bypasses Ingress entirely ✅

### Understanding the Architecture

**With Ingress (Production-like):**
```
Browser → Domain (video2mp3.com)
       ↓
/etc/hosts → 192.168.49.2 (minikube IP)
       ↓
Ingress Controller (nginx on minikube)
       ↓
Routes based on hostname rules
       ↓
Gateway Service (ClusterIP)
       ↓
Gateway Pod
```

**With Port Forwarding (Development):**
```
Browser → Domain (video2mp3.com)
       ↓
/etc/hosts → 127.0.0.1 (localhost)
       ↓
kubectl port-forward (listening on localhost)
       ↓
Direct tunnel to Gateway Service
       ↓
Gateway Pod
```

**Key Difference:** Port forwarding creates a direct tunnel, bypassing Ingress.

## Related Issues & Solutions

### Auth Service Login Problems
If you encounter issues with the auth service `/login` endpoint:
- **404 errors:** Check [Auth Service Solution Guide](../auth/solution-auth-login.md)
- **MySQL connection errors:** See MySQL configuration section in auth solution guide
- **Port forwarding setup:** Both guides use the same port forwarding approach

### Quick Start Script

A convenience script is provided at the project root:

```bash
# Start all services at once
./start-services.sh
```

This script:
- Starts gateway (port 80 for clean URLs), auth (5000), and RabbitMQ (15672)
- Shows URLs and PIDs for each service
- Provides test commands
- Uses sudo for port 80 (will prompt for password)

**Stop all services:**
```bash
sudo pkill -f 'kubectl port-forward'
```