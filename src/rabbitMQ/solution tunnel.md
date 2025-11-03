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
kubectl port-forward service/gateway 8080:8080 > /tmp/gateway-pf.log 2>&1 &
```
Access at: http://localhost:8080 or http://video2mp3.com:8080

**Auth Service:**
```bash
kubectl port-forward service/auth 5000:5000 > /tmp/auth-pf.log 2>&1 &
```
Access at: http://localhost:5000

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