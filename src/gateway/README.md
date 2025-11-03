# Gateway Service

API Gateway and file handling service for the video2mp3 microservices system.

## Overview

The Gateway service is the main entry point for clients and provides:
- User login (proxies to Auth service)
- Video file upload with JWT validation
- MP3 file download
- RabbitMQ message publishing for video processing
- MongoDB GridFS integration for file storage

## Architecture

```
Client
  ↓
Gateway Service (Flask, Port 8080)
  ├→ Auth Service:5000 (login, token validation)
  ├→ MongoDB:27017 (video/MP3 storage via GridFS)
  └→ RabbitMQ:5672 (publish conversion jobs)
```

## Endpoints

### POST /login
Proxy to Auth service for user authentication.

**Request:**
```bash
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login
```

**Response:**
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### POST /upload
Upload video file for conversion (requires JWT token).

**Request:**
```bash
curl -X POST \
  -H "Authorization: Bearer <token>" \
  -F "file=@video.mp4" \
  http://video2mp3.com/upload
```

**Process:**
1. Validates JWT token with Auth service
2. Stores video in MongoDB (GridFS) → gets `video_fid`
3. Publishes message to RabbitMQ `video` queue with metadata
4. Returns success response

**Response:**
```
success!
```

### GET /download?fid=<file_id>
Download converted MP3 file (requires JWT token).

**Request:**
```bash
curl -X GET \
  -H "Authorization: Bearer <token>" \
  "http://video2mp3.com/download?fid=<ObjectId>" \
  -o output.mp3
```

**Process:**
1. Validates JWT token with Auth service
2. Retrieves MP3 from MongoDB using `fid`
3. Streams file to client

## Configuration

### Environment Variables (ConfigMap)
- `AUTH_SVC_ADDRESS` - Auth service address (e.g., "auth:5000")
- `MONGODB_HOST` - MongoDB host IP (e.g., 192.168.49.1 for minikube)
- `MONGODB_PORT` - MongoDB port (27017)

### Secrets
- Auth service credentials (if needed)

### Service Discovery
The `AUTH_SVC_ADDRESS: "auth:5000"` uses Kubernetes internal DNS:
- `auth` resolves to the auth service ClusterIP
- Kubernetes load balances requests across auth pods (round-robin by default)

## Kubernetes Service Types

### ClusterIP (Default)
- Gives an internal IP address within the cluster
- Only accessible from within Kubernetes cluster
- Used for internal service-to-service communication

### Ingress
Gateway needs external access, so we use an Ingress resource:
- Routes external traffic based on hostname/path rules
- Enables access to gateway from outside the cluster
- Example: `video2mp3.com` → `gateway:8080`

**Ingress Rules:**
```yaml
rules:
  - host: video2mp3.com
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: gateway
              port:
                number: 8080
```

Multiple hosts can be configured with different routing rules to different services.

## Setup & Configuration

### Prerequisites
```bash
# Add hostname to /etc/hosts
sudo vim /etc/hosts
# Add: 127.0.0.1 video2mp3.com
```

### Minikube Setup
```bash
# Start minikube
minikube start

# Enable ingress addon
minikube addons list
minikube addons enable ingress

# Verify ingress is enabled
kubectl get pods -n ingress-nginx
```

### Port Forwarding (Development)
For local development, use port forwarding instead of Ingress:

```bash
# Gateway on port 80 (clean URLs, requires sudo)
sudo kubectl port-forward service/gateway 80:8080

# Or on port 8080 (no sudo needed)
kubectl port-forward service/gateway 8080:8080
```

See [../../src/rabbitMQ/solution tunnel.md](../rabbitMQ/solution%20tunnel.md) for detailed networking guide.

## Docker Build & Deploy

### Build Docker Image
```bash
cd src/gateway
docker build -t dksahuji/video2mp3-gateway:latest .
```

### Push to Docker Hub
```bash
docker push dksahuji/video2mp3-gateway:latest
```

## Kubernetes Deployment

### Deploy Gateway Service
```bash
cd src/gateway/manifests
kubectl apply -f ./
```

This creates:
- `deployment.apps/gateway` - 2 replicas with RollingUpdate strategy
- `configmap/gateway-configmap` - Environment configuration
- `secret/gateway-secret` - Sensitive credentials
- `service/gateway` - ClusterIP service on port 8080
- `ingress/gateway-ingress` - External access via video2mp3.com

### Undeploy
```bash
kubectl delete -f ./
```

### Scale Replicas
```bash
kubectl scale deployment gateway --replicas=4
kubectl get pods -l app=gateway
```

## Monitoring & Debugging

### Check Deployment Status
```bash
# View pods
kubectl get pods -l app=gateway

# View service
kubectl get service gateway

# View ingress
kubectl get ingress gateway-ingress

# View logs
kubectl logs -l app=gateway --tail=50 -f
```

### Shell into Pod
```bash
kubectl exec -it deployment/gateway -- /bin/bash

# Test MongoDB connection
python3 -c "import pymongo; print(pymongo.MongoClient('mongodb://192.168.49.1:27017/').server_info())"

# Test Auth service connection
curl -v http://auth:5000/login
```

### Test Gateway Service
```bash
# Port forward
kubectl port-forward service/gateway 8080:8080

# Login
TOKEN=$(curl -X POST -u "dksahuji@gmail.com:Admin123" http://localhost:8080/login 2>/dev/null)

# Upload video
curl -X POST -F "file=@video.mp4" \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/upload

# Download MP3 (after conversion completes)
curl -X GET "http://localhost:8080/download?fid=<ObjectId>" \
  -H "Authorization: Bearer $TOKEN" \
  -o output.mp3
```

## Common Issues

### Upload Returns 500 Error
**Problem:** Can't connect to MongoDB

**Check MongoDB connection:**
```bash
kubectl exec deployment/gateway -- python3 -c \
  "import pymongo; pymongo.MongoClient('mongodb://192.168.49.1:27017/').server_info()"
```

**Solution:** Ensure MongoDB is configured to listen on 0.0.0.0 (see setup-host.sh)

### Auth Validation Fails
**Problem:** Can't reach Auth service

**Check Auth service:**
```bash
kubectl get service auth
kubectl get endpoints auth
```

**Test from pod:**
```bash
kubectl exec deployment/gateway -- curl -v http://auth:5000/login
```

### File Upload Fails
**Problem:** RabbitMQ not accessible

**Check RabbitMQ:**
```bash
kubectl get pods -l app=rabbitmq
kubectl logs rabbitmq-0
```

## Message Format

When a video is uploaded, Gateway publishes to RabbitMQ:

```json
{
  "video_fid": "<MongoDB ObjectId>",
  "mp3_fid": null,
  "username": "dksahuji@gmail.com"
}
```

Queue: `video` (hardcoded in storage/util.py)

## Files

- `server.py` - Flask application with /login, /upload, /download endpoints
- `storage/util.py` - GridFS upload/download logic
- `auth_svc/access.py` - Auth service login proxy
- `auth/validate.py` - JWT token validation
- `Dockerfile` - Python 3.12-slim with build tools
- `pyproject.toml` - Dependencies: flask, flask-pymongo, pika, pymongo
- `manifests/` - Kubernetes deployment files
  - `gateway-deploy.yaml` - Deployment with 2 replicas
  - `configmap.yaml.template` - Environment variables (uses ${MONGODB_HOST})
  - `secret.yaml` - Sensitive credentials
  - `service.yaml` - ClusterIP service on port 8080
  - `ingress.yaml` - Ingress routing for video2mp3.com

## Development Workflow

```bash
# 1. Make code changes
vim server.py

# 2. Rebuild Docker image
docker build -t dksahuji/video2mp3-gateway:latest .
docker push dksahuji/video2mp3-gateway:latest

# 3. Restart deployment
kubectl rollout restart deployment/gateway
kubectl rollout status deployment/gateway

# 4. Check logs
kubectl logs -l app=gateway --tail=50 -f

# 5. Test changes
curl -X POST -u "user:pass" http://video2mp3.com/login
```

## Load Balancing

Kubernetes automatically load balances requests to gateway pods:
- **Algorithm:** Round-robin by default
- **Replicas:** 2 (configurable in gateway-deploy.yaml)
- **Max Surge:** 3 pods during rolling updates

## Data Flow

### Upload Flow:
```
Client → Gateway → Auth (validate token)
              ↓
         MongoDB (store video)
              ↓
         RabbitMQ (publish message)
              ↓
         Response to Client
```

### Download Flow:
```
Client → Gateway → Auth (validate token)
              ↓
         MongoDB (retrieve MP3)
              ↓
         Stream to Client
```

## Resources

- [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Flask Documentation](https://flask.palletsprojects.com/)
- [MongoDB GridFS](https://www.mongodb.com/docs/manual/core/gridfs/)
- [Pika (RabbitMQ) Documentation](https://pika.readthedocs.io/)

## Related Documentation

- **Port forwarding guide:** [../rabbitMQ/solution tunnel.md](../rabbitMQ/solution%20tunnel.md)
- **General debugging:** [../../DEBUGGING-GUIDE.md](../../DEBUGGING-GUIDE.md)
- **Project overview:** [../../README-COMPLETE.md](../../README-COMPLETE.md)