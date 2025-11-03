# Video2MP3 - Quick Start Guide

## 🚀 Four-Command Setup (First Time)

```bash
./setup-host.sh          # 1. Setup MySQL/MongoDB permissions (first time only)
./deploy.sh              # 2. Deploy to Kubernetes
./start-services.sh      # 3. Start port forwarding
# 4. Test: curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login
```

## 🔄 After First Setup (Daily Use)

```bash
./deploy.sh              # 1. Deploy to Kubernetes
./start-services.sh      # 2. Start port forwarding
# 3. Test: curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login
```

## 📋 Available Scripts

| Script | Purpose | When to Run | Requires Sudo |
|--------|---------|-------------|---------------|
| `./setup-host.sh` | Setup MySQL/MongoDB access | First time only (or when minikube IP changes) | Yes |
| `./deploy.sh` | Deploy all services to Kubernetes | Every deployment | No |
| `./undeploy.sh` | Remove all services from Kubernetes | When cleaning up | Yes (for pkill) |
| `./start-services.sh` | Start port forwarding for local access | After every deploy | Yes (port 80) |

## 🎯 Common Workflows

### First Time Setup

```bash
# 1. Setup host machine (MySQL/MongoDB permissions)
./setup-host.sh

# 2. Deploy everything
./deploy.sh

# 3. Start port forwarding
./start-services.sh

# 4. Test login
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login

# Expected: JWT token
```

**Note:** Only run `./setup-host.sh` once (or when minikube IP changes)

### Daily Development

```bash
# Morning: Start services
./start-services.sh

# Work on code...

# Evening: Stop services
sudo pkill -f 'kubectl port-forward'
```

### Make Code Changes

```bash
# 1. Edit code
vim src/gateway/server.py

# 2. Rebuild Docker image
cd src/gateway
docker build -t dksahuji/video2mp3-gateway:latest .
docker push dksahuji/video2mp3-gateway:latest

# 3. Restart deployment
kubectl rollout restart deployment/gateway
kubectl rollout status deployment/gateway

# 4. Test changes
curl -X POST ... http://video2mp3.com/upload
```

### Clean Reset

```bash
# Remove everything
./undeploy.sh

# Redeploy fresh
./deploy.sh
./start-services.sh
```

## 📍 Service URLs (with port forwarding active)

| Service | URL | Credentials |
|---------|-----|-------------|
| Gateway (login) | http://video2mp3.com/login | dksahuji@gmail.com:Admin123 |
| Gateway (upload) | http://video2mp3.com/upload | Bearer token |
| Auth (direct) | http://localhost:5000 | - |
| RabbitMQ UI | http://localhost:15672 | guest:guest |

## 🔍 Useful Commands

### Check Status
```bash
kubectl get pods                    # View all pods
kubectl get services                # View all services
kubectl logs -l app=gateway -f      # Follow gateway logs
kubectl logs -l app=auth -f         # Follow auth logs
```

### Debug Issues
```bash
# Check pod logs
kubectl logs -l app=gateway --tail=50

# Check configmap values
kubectl get configmap gateway-configmap -o yaml

# Describe pod for events
kubectl describe pod <pod-name>

# Shell into pod
kubectl exec -it deployment/gateway -- /bin/bash
```

### View Configuration
```bash
# Check what IP is configured
kubectl get configmap auth-configmap -o yaml | grep MYSQL_HOST
kubectl get configmap gateway-configmap -o yaml | grep MONGODB_HOST

# Check port forwards
ps aux | grep "kubectl port-forward"
```

## 🛠️ Troubleshooting

### Port forwarding not working?
```bash
# Stop all existing forwards
sudo pkill -f 'kubectl port-forward'

# Restart
./start-services.sh
```

### Upload returns 500 error?
```bash
# Check MongoDB connection
kubectl exec deployment/gateway -- python3 -c "import pymongo; pymongo.MongoClient('mongodb://192.168.49.1:27017/').server_info()"

# Check gateway logs
kubectl logs -l app=gateway --tail=50
```

### Login returns 404?
```bash
# Check auth pod is running
kubectl get pods -l app=auth

# Check auth logs
kubectl logs -l app=auth --tail=50

# Verify deployed code
kubectl exec deployment/auth -- grep -B 1 "def login" /app/server.py
```

### Deployment fails?
```bash
# Check current resources
kubectl get all

# Check events
kubectl get events --sort-by='.lastTimestamp'

# Redeploy
./undeploy.sh
./deploy.sh
```

## 📚 More Information

- **Complete deployment guide:** [DEPLOYMENT.md](./DEPLOYMENT.md)
- **Debugging guide:** [DEBUGGING-GUIDE.md](./DEBUGGING-GUIDE.md)
- **Full documentation:** [README-COMPLETE.md](./README-COMPLETE.md)
- **Documentation index:** [DOCUMENTATION-INDEX.md](./DOCUMENTATION-INDEX.md)

## 🎬 Complete End-to-End Workflow

```bash
# 1. Setup (first time only)
./setup-host.sh

# 2. Configure Gmail for notifications (edit .env file)
# IMPORTANT: Do NOT use quotes around values
cat > .env << 'EOF'
GMAIL_ADDRESS=your-email@gmail.com
GMAIL_PASSWORD=your-16-char-app-password
EOF

# 3. Deploy and start services
./deploy.sh
./start-services.sh

# 4. Login and get JWT token
TOKEN=$(curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login 2>/dev/null)
echo $TOKEN

# 5. Upload video file
curl -X POST -F "file=@video.mp4" \
  -H "Authorization: Bearer $TOKEN" \
  http://video2mp3.com/upload

# 6. Monitor conversion progress
kubectl logs -l app=converter -f

# 7. Monitor email notification
kubectl logs -l app=notification -f

# 8. Check your email for the mp3_fid (file ID)

# 9. Download the converted MP3
curl --output downloaded.mp3 -X GET \
  -H "Authorization: Bearer $TOKEN" \
  "http://video2mp3.com/download?fid=<file_id_from_email>"
```

## ⚡ Cheat Sheet

```bash
# Setup host (first time only)
./setup-host.sh

# Deploy
./deploy.sh

# Undeploy
./undeploy.sh

# Port forward
./start-services.sh

# Stop port forward
sudo pkill -f 'kubectl port-forward'

# View pods
kubectl get pods

# View logs
kubectl logs -l app=gateway --tail=50
kubectl logs -l app=converter -f
kubectl logs -l app=notification -f

# Restart service
kubectl rollout restart deployment/gateway

# Check config
kubectl get configmap gateway-configmap -o yaml

# Test login
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login

# Test upload (after getting token)
TOKEN=$(curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login 2>/dev/null)
curl -X POST -F "file=@video.mp4" -H "Authorization: Bearer $TOKEN" http://video2mp3.com/upload

# Download MP3 (replace <file_id> with ID from email)
curl --output downloaded.mp3 -X GET \
  -H "Authorization: Bearer $TOKEN" \
  "http://video2mp3.com/download?fid=<file_id>"
```

## 🎓 Learn More

**New to Kubernetes?**
- Start with [README-COMPLETE.md](./README-COMPLETE.md) - Architecture section
- Then read [DEBUGGING-GUIDE.md](./DEBUGGING-GUIDE.md) - Debugging methodologies

**Want to understand the setup?**
- Read [DEPLOYMENT.md](./DEPLOYMENT.md) - Deployment options
- Read auth/gateway solution docs for troubleshooting examples

**Ready to deploy to production?**
- See [DEPLOYMENT.md](./DEPLOYMENT.md) - Production deployment section
- Set custom hosts before deploying
