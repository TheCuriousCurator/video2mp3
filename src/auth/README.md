# Auth Service

JWT-based authentication service for the video2mp3 microservices system.

## Overview

The Auth service provides:
- User authentication via HTTP Basic Auth
- JWT token generation (24-hour expiry)
- Token validation for other services
- MySQL-backed user storage

## Architecture

```
Client Request
    ↓
POST /login (Basic Auth: email:password)
    ↓
Auth Service → MySQL (192.168.49.1:3306)
    ↓
Returns JWT Token (24h expiry)
```

## Endpoints

### POST /login
Authenticate user and return JWT token.

**Request:**
```bash
curl -X POST -u "dksahuji@gmail.com:Admin123" http://localhost:5000/login
```

**Response:**
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### POST /validate
Validate JWT token.

**Request:**
```bash
curl -X POST -H "Authorization: Bearer <token>" http://localhost:5000/validate
```

**Response:**
```json
{
  "username": "dksahuji@gmail.com",
  "admin": true,
  "exp": 1730822400,
  "iat": 1730736000
}
```

## Database Setup

### Prerequisites
```bash
sudo apt-get install libmysqlclient-dev
```

### Initialize MySQL Database
```bash
# Create database and user table
sudo mysql -u root < init.sql
```

### Verify Database Setup
```bash
sudo mysql -u root
```
```sql
show databases;
use auth;
show tables;
describe user;
select * from user;
```

### Default User
- **Email:** dksahuji@gmail.com
- **Password:** Admin123
- **Admin:** true

## Configuration

### Environment Variables (ConfigMap)
- `MYSQL_HOST` - MySQL host IP (e.g., 192.168.49.1 for minikube)
- `MYSQL_USER` - Database user (auth_user)
- `MYSQL_DB` - Database name (auth)
- `MYSQL_PORT` - MySQL port (3306)

### Secrets
- `MYSQL_PASSWORD` - Database password
- `JWT_SECRET` - Secret key for JWT signing

## Docker Build & Deploy

### Build Docker Image
```bash
cd src/auth
docker build -t dksahuji/video2mp3-auth:latest .
```

### Push to Docker Hub
```bash
# Login to Docker Hub
docker login

# Tag image (if needed)
docker tag <image-id> dksahuji/video2mp3-auth:latest

# List images
docker image ls

# Push image
docker push dksahuji/video2mp3-auth:latest
```

## Kubernetes Deployment

### Deploy Auth Service
```bash
cd src/auth/manifests
kubectl apply -f ./
```

This creates:
- `deployment.apps/auth` - 2 replicas with RollingUpdate strategy
- `configmap/auth-configmap` - Environment configuration
- `secret/auth-secret` - Sensitive credentials
- `service/auth` - ClusterIP service on port 5000

### Undeploy
```bash
kubectl delete -f ./
```

### Scale Replicas
```bash
# Scale to 6 replicas
kubectl scale deployment auth --replicas=6

# Check pods
kubectl get pods -l app=auth
```

## Monitoring & Debugging

### Check Deployment Status
```bash
# View pods
kubectl get pods -l app=auth

# View service
kubectl get service auth

# View logs
kubectl logs -l app=auth --tail=50 -f

# Describe pod
kubectl describe pod <pod-name>
```

### Shell into Pod
```bash
kubectl exec -it deployment/auth -- /bin/bash

# Inside pod - show environment variables
env

# Test MySQL connection
mysql -u auth_user -p -h 192.168.49.1 auth -e "SELECT * FROM user;"
```

### View Deployed Code
```bash
kubectl exec deployment/auth -- cat /app/server.py
```

### Test Auth Service
```bash
# Port forward to local
kubectl port-forward service/auth 5000:5000

# Test login
curl -X POST -u "dksahuji@gmail.com:Admin123" http://localhost:5000/login

# Test validate (use token from login)
curl -X POST -H "Authorization: Bearer <token>" http://localhost:5000/validate
```

## Common Issues

### MySQL Connection Refused
**Problem:** Pods can't connect to MySQL on host

**Solutions:**
1. Update MySQL bind-address to 0.0.0.0
2. Grant MySQL permissions from minikube network (192.168.49.%)

See [solution-auth-login.md](./solution-auth-login.md) for detailed debugging steps.

### 404 on /login Endpoint
**Problem:** Route not registered

**Check deployed code:**
```bash
kubectl exec deployment/auth -- grep -B 1 "def login" /app/server.py
```

Should show: `@server.route("/login", methods=["POST"])`

If missing `@`, rebuild and redeploy Docker image.

### Access Denied for User
**Problem:** MySQL user doesn't have permissions from pod's IP

**Solution:**
```bash
sudo mysql -u root -e "
CREATE USER IF NOT EXISTS 'auth_user'@'192.168.49.%' IDENTIFIED BY 'Auth123';
GRANT ALL PRIVILEGES ON auth.* TO 'auth_user'@'192.168.49.%';
FLUSH PRIVILEGES;
"
```

## JWT Token Structure

```json
{
  "username": "dksahuji@gmail.com",
  "admin": true,
  "exp": 1730822400,  // Expiry (24 hours from iat)
  "iat": 1730736000   // Issued at timestamp
}
```

## Files

- `server.py` - Flask application with /login and /validate endpoints
- `init.sql` - Database schema and default user
- `Dockerfile` - Python 3.12-slim with MySQL client
- `pyproject.toml` - Dependencies: flask, flask-mysqldb, pyjwt
- `manifests/` - Kubernetes deployment files
  - `auth-deploy.yaml` - Deployment with 2 replicas
  - `configmap.yaml.template` - Environment variables (uses ${MYSQL_HOST})
  - `secret.yaml` - Sensitive credentials
  - `service.yaml` - ClusterIP service on port 5000
- `solution-auth-login.md` - Comprehensive debugging guide

## Development Workflow

```bash
# 1. Make code changes
vim server.py

# 2. Rebuild Docker image
docker build -t dksahuji/video2mp3-auth:latest .
docker push dksahuji/video2mp3-auth:latest

# 3. Restart deployment
kubectl rollout restart deployment/auth
kubectl rollout status deployment/auth

# 4. Verify changes
kubectl exec deployment/auth -- cat /app/server.py | grep "your change"

# 5. Check logs
kubectl logs -l app=auth --tail=50 -f
```

## Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/concepts/overview/working-with-objects/)
- [Deployment API Reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/deployment-v1/)
- [Flask Documentation](https://flask.palletsprojects.com/)
- [PyJWT Documentation](https://pyjwt.readthedocs.io/)

## Related Documentation

- **Comprehensive debugging:** [solution-auth-login.md](./solution-auth-login.md)
- **General debugging guide:** [../../DEBUGGING-GUIDE.md](../../DEBUGGING-GUIDE.md)
- **Project overview:** [../../README-COMPLETE.md](../../README-COMPLETE.md)