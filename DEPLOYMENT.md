# Deployment Guide

## Quick Reference

```bash
# Deploy everything
./deploy.sh

# Remove everything
./undeploy.sh

# Start port forwarding
./start-services.sh
```

## Prerequisites

### First Time Setup - Host Machine Preparation

Before deploying, run the host setup script to configure MySQL and MongoDB:

```bash
./setup-host.sh
```

**What it does:**
1. Auto-detects minikube subnet (e.g., 192.168.49.%)
2. Configures MySQL:
   - Updates `bind-address` to `0.0.0.0`
   - Creates MySQL user `auth_user@192.168.49.%`
   - Grants permissions on `auth` database
3. Configures MongoDB:
   - Updates `bindIp` to `0.0.0.0`
   - Verifies MongoDB is accessible from minikube network
4. Tests connectivity from host and pods

**When to run:**
- First time setting up the project
- When minikube IP changes (different subnet)
- When you get "access denied" or "connection refused" errors

**Note:** This only needs to be run once per machine (or when minikube network changes)

### Configure Gmail for Notifications

Create a `.env` file in the project root with your Gmail credentials:

```bash
GMAIL_ADDRESS=your-email@gmail.com
GMAIL_PASSWORD=your-16-char-app-password
```

**IMPORTANT:**
- Do NOT use quotes around values
- Use a Gmail App Password (not your regular password)
- Requires 2FA enabled on Gmail account

**Why no quotes?**
The `envsubst` command in deploy.sh adds quotes when processing templates. Using quotes in `.env` will cause double-quoting and YAML parsing errors:

```yaml
# Wrong (with quotes in .env):
GMAIL_ADDRESS: ""your-email@gmail.com""  # ❌ YAML parsing error

# Correct (no quotes in .env):
GMAIL_ADDRESS: "your-email@gmail.com"    # ✅ Valid YAML
```

**Generate Gmail App Password:**
1. Go to Google Account settings: https://myaccount.google.com/
2. Navigate to Security → 2-Step Verification
3. Scroll down to "App passwords"
4. Generate a new app password for "Mail"
5. Copy the 16-character password to `.env`

## Automated Deployment (Recommended)

The `deploy.sh` script automatically detects your minikube host IP and deploys all services:

```bash
./deploy.sh
```

**What it does:**
1. Auto-detects minikube IP (e.g., 192.168.49.2)
2. Calculates host IP (e.g., 192.168.49.1)
3. Substitutes `${MYSQL_HOST}` and `${MONGODB_HOST}` in template files
4. Deploys all services to Kubernetes
5. Waits for deployments to be ready

**After deployment:**
```bash
# Start port forwarding
./start-services.sh

# Test login
curl -X POST -u 'dksahuji@gmail.com:Admin123' http://video2mp3.com/login
```

## Manual Deployment

If you prefer manual control or the script doesn't work:

### Step 1: Detect Host IP
```bash
# Get minikube IP
minikube ip
# Example output: 192.168.49.2

# Calculate host IP (change last octet to .1)
# If minikube IP is 192.168.49.2, host IP is 192.168.49.1
```

### Step 2: Set Environment Variables
```bash
export MYSQL_HOST="192.168.49.1"
export MONGODB_HOST="192.168.49.1"
export MYSQL_PORT="3306"
export MONGODB_PORT="27017"
```

### Step 3: Deploy with envsubst
```bash
# Deploy auth
envsubst < src/auth/manifests/configmap.yaml.template | kubectl apply -f -
kubectl apply -f src/auth/manifests/secret.yaml
kubectl apply -f src/auth/manifests/auth-deploy.yaml
kubectl apply -f src/auth/manifests/service.yaml

# Deploy gateway
envsubst < src/gateway/manifests/configmap.yaml.template | kubectl apply -f -
kubectl apply -f src/gateway/manifests/secret.yaml
kubectl apply -f src/gateway/manifests/gateway-deploy.yaml
kubectl apply -f src/gateway/manifests/service.yaml
kubectl apply -f src/gateway/manifests/ingress.yaml

# Deploy RabbitMQ
kubectl apply -f src/rabbitMQ/manifests/

# Deploy converter
kubectl apply -f src/converter/manifests/
```

## Alternative: Direct Edit (No Templates)

If `envsubst` is not available:

### Step 1: Copy templates to actual files
```bash
cp src/auth/manifests/configmap.yaml.template src/auth/manifests/configmap.yaml
cp src/gateway/manifests/configmap.yaml.template src/gateway/manifests/configmap.yaml
```

### Step 2: Replace variables with sed
```bash
# Detect host IP
HOST_IP=$(minikube ip | sed 's/\.[0-9]*$/.1/')

# Replace in auth configmap
sed -i "s/\${MYSQL_HOST}/$HOST_IP/g" src/auth/manifests/configmap.yaml
sed -i "s/\${MYSQL_PORT}/3306/g" src/auth/manifests/configmap.yaml

# Replace in gateway configmap
sed -i "s/\${MONGODB_HOST}/$HOST_IP/g" src/gateway/manifests/configmap.yaml
sed -i "s/\${MONGODB_PORT}/27017/g" src/gateway/manifests/configmap.yaml
```

### Step 3: Apply normally
```bash
kubectl apply -f src/auth/manifests/
kubectl apply -f src/gateway/manifests/
kubectl apply -f src/rabbitMQ/manifests/
kubectl apply -f src/converter/manifests/
```

## For Production Deployment

For production, you'll use actual service hostnames instead of IPs:

```bash
export MYSQL_HOST="mysql.production.example.com"
export MONGODB_HOST="mongodb.production.example.com"
export MYSQL_PORT="3306"
export MONGODB_PORT="27017"

./deploy.sh
```

Or create a production-specific script:

```bash
# deploy-production.sh
export MYSQL_HOST="mysql.production.example.com"
export MONGODB_HOST="mongodb.production.example.com"

envsubst < src/auth/manifests/configmap.yaml.template | kubectl apply -f -
envsubst < src/gateway/manifests/configmap.yaml.template | kubectl apply -f -
# ... rest of deployments
```

## Verification

After deployment, verify the configuration:

```bash
# Check auth configmap
kubectl get configmap auth-configmap -o yaml | grep MYSQL_HOST

# Check gateway configmap
kubectl get configmap gateway-configmap -o yaml | grep MONGODB_HOST

# Check pods
kubectl get pods

# Check logs
kubectl logs -l app=auth --tail=20
kubectl logs -l app=gateway --tail=20
```

## Troubleshooting

### envsubst not found

Install `gettext`:
```bash
# Ubuntu/Debian
sudo apt-get install gettext

# macOS
brew install gettext
```

### Wrong IP detected

Manually override:
```bash
export MYSQL_HOST="192.168.49.1"
export MONGODB_HOST="192.168.49.1"
./deploy.sh
```

### Variables not substituted

Make sure to export variables before running deploy.sh:
```bash
export MYSQL_HOST="192.168.49.1"
```

Not just setting them:
```bash
MYSQL_HOST="192.168.49.1"  # ❌ Won't work with envsubst
```

## File Organization

```
video2mp3/
├── deploy.sh                           # Automated deployment script
├── start-services.sh                   # Port forwarding script
├── src/
│   ├── auth/manifests/
│   │   ├── configmap.yaml             # Old: hardcoded (keep for reference)
│   │   ├── configmap.yaml.template    # New: uses ${MYSQL_HOST}
│   │   ├── secret.yaml
│   │   ├── auth-deploy.yaml
│   │   └── service.yaml
│   └── gateway/manifests/
│       ├── configmap.yaml             # Old: hardcoded (keep for reference)
│       ├── configmap.yaml.template    # New: uses ${MONGODB_HOST}
│       ├── secret.yaml
│       ├── gateway-deploy.yaml
│       ├── service.yaml
│       └── ingress.yaml
```

## Undeployment

### Automated Undeployment (Recommended)

Remove all video2mp3 services from Kubernetes:

```bash
./undeploy.sh
```

**What it does:**
1. Stops all port forwards
2. Deletes all deployments (auth, gateway, converter)
3. Deletes all services
4. Deletes all configmaps and secrets
5. Deletes RabbitMQ StatefulSet and PVC
6. Deletes Ingress resources
7. Verifies all resources removed

**What it does NOT remove:**
- Docker images (on your machine)
- MySQL/MongoDB data (on host machine)
- PersistentVolumes (only PVCs)

### Manual Undeployment

If you prefer manual control:

```bash
# Stop port forwards
sudo pkill -f 'kubectl port-forward'

# Delete deployments
kubectl delete deployment auth gateway converter

# Delete services
kubectl delete service auth gateway rabbitmq

# Delete StatefulSets
kubectl delete statefulset rabbitmq

# Delete ConfigMaps
kubectl delete configmap auth-configmap gateway-configmap converter-configmap rabbitmq-configmap

# Delete Secrets
kubectl delete secret auth-secret gateway-secret converter-secret rabbitmq-secret

# Delete Ingress
kubectl delete ingress gateway-ingress rabbitmq-ingress

# Delete PVCs
kubectl delete pvc rabbitmq-pvc
```

### Partial Undeployment

Remove specific services:

```bash
# Remove only gateway
kubectl delete deployment gateway
kubectl delete service gateway
kubectl delete configmap gateway-configmap
kubectl delete secret gateway-secret

# Remove only auth
kubectl delete deployment auth
kubectl delete service auth
kubectl delete configmap auth-configmap
kubectl delete secret auth-secret

# Remove only converter
kubectl delete deployment converter
kubectl delete configmap converter-configmap
kubectl delete secret converter-secret

# Remove only RabbitMQ
kubectl delete statefulset rabbitmq
kubectl delete service rabbitmq
kubectl delete pvc rabbitmq-pvc
```

### Clean Slate (Complete Reset)

For a complete reset including data:

```bash
# 1. Undeploy everything
./undeploy.sh

# 2. Delete all PersistentVolumes (if any)
kubectl delete pv --all

# 3. Clean up host data (CAREFUL - deletes data!)
# MySQL (optional - only if you want to reset DB)
sudo mysql -u root -e "DROP DATABASE IF EXISTS auth;"

# MongoDB (optional - only if you want to reset collections)
mongosh --eval "use videos; db.dropDatabase(); use mp3s; db.dropDatabase();"

# 4. Remove Docker images (optional)
docker rmi dksahuji/video2mp3-auth:latest
docker rmi dksahuji/video2mp3-gateway:latest
docker rmi dksahuji/video2mp3-converter:latest

# 5. Redeploy fresh
./deploy.sh
```

## Lifecycle Management

### Development Workflow

```bash
# 1. Initial deployment
./deploy.sh

# 2. Start working
./start-services.sh

# 3. Make code changes
vim src/gateway/server.py

# 4. Rebuild and redeploy
cd src/gateway
docker build -t dksahuji/video2mp3-gateway:latest .
docker push dksahuji/video2mp3-gateway:latest
kubectl rollout restart deployment/gateway

# 5. Stop working
sudo pkill -f 'kubectl port-forward'

# 6. Clean up (end of day)
./undeploy.sh
```

### Testing Changes

```bash
# Deploy
./deploy.sh

# Test
./start-services.sh
curl -X POST -u 'user:pass' http://video2mp3.com/login

# If issues, check logs
kubectl logs -l app=gateway --tail=50

# Clean up
./undeploy.sh
```

### Production Deployment

```bash
# 1. Deploy to production
export MYSQL_HOST="mysql-prod.example.com"
export MONGODB_HOST="mongodb-prod.example.com"
./deploy.sh

# 2. Verify
kubectl get pods
kubectl get services

# 3. If issues, rollback
./undeploy.sh

# 4. Fix issues and redeploy
./deploy.sh
```

## Best Practices

1. **Use templates (*.yaml.template)** - Version controlled with variables
2. **Use deploy.sh** - Automated, consistent deployments
3. **Use undeploy.sh** - Clean removal of resources
4. **Don't commit generated files** - Add `configmap.yaml` to `.gitignore` if generated
5. **Test locally first** - Use minikube before production
6. **Verify after deployment** - Always check configmaps and logs
7. **Clean up when done** - Run undeploy.sh to free resources
