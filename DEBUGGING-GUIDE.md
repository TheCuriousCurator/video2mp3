# Video2MP3 Debugging Guide

## Overview

This guide documents all issues encountered, debugging methodologies, and solutions implemented in the video2mp3 microservices project. It serves as both a troubleshooting reference and a learning resource for debugging Kubernetes, Docker, and microservices applications.

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Essential Debugging Tools](#essential-debugging-tools)
3. [Common Issues and Solutions](#common-issues-and-solutions)
4. [Debugging Methodologies](#debugging-methodologies)
5. [Lessons Learned](#lessons-learned)

## Quick Reference

### Start Services (Clean URLs)
```bash
./start-services.sh
# Prompts for sudo password once
# Gateway accessible at: http://video2mp3.com/login (no port number!)
```

### Test Login
```bash
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login
# Returns JWT token
```

### Stop All Services
```bash
sudo pkill -f 'kubectl port-forward'
```

### View Logs
```bash
# Port forward logs
tail -f /tmp/gateway-pf.log
tail -f /tmp/auth-pf.log
tail -f /tmp/rabbitmq-pf.log

# Pod logs
kubectl logs -l app=auth --tail=50 -f
kubectl logs -l app=gateway --tail=50 -f
kubectl logs -l app=converter -f
kubectl logs -l app=notification -f
```

## Essential Debugging Tools

### 1. kubectl Commands

**Check pod status:**
```bash
kubectl get pods -l app=auth
kubectl describe pod <pod-name>
kubectl logs <pod-name> --tail=50
kubectl logs -l app=auth --tail=50 -f  # Follow logs
```

**Inspect deployed code:**
```bash
# View files inside pod
kubectl exec deployment/auth -- cat /app/server.py

# Interactive shell
kubectl exec -it deployment/auth -- /bin/bash

# Run commands
kubectl exec deployment/auth -- python3 -c "from server import server; print(server.url_map)"
```

**Check services:**
```bash
kubectl get services
kubectl describe service gateway
kubectl get endpoints gateway  # See which pods service routes to
```

**Check Ingress:**
```bash
kubectl get ingress --all-namespaces
kubectl describe ingress <ingress-name>
```

### 2. Network Debugging

**Test port connectivity:**
```bash
# From host
nc -zv 192.168.49.1 3306

# From pod
kubectl exec deployment/auth -- nc -zv 192.168.49.1 3306
```

**Check what's listening on ports:**
```bash
ss -tlnp | grep 3306
netstat -tlnp | grep :80
sudo lsof -i :80
```

**Test HTTP endpoints:**
```bash
# Basic test
curl -v http://localhost:5000/login

# With authentication
curl -X POST -u "user:pass" http://localhost/login

# Follow redirects
curl -L http://localhost/login

# Check response headers
curl -I http://localhost/login
```

### 3. Docker & Image Debugging

**Check image tags:**
```bash
docker images | grep video2mp3
```

**Rebuild and push:**
```bash
cd src/auth
docker build -t dksahuji/video2mp3-auth:latest .
docker push dksahuji/video2mp3-auth:latest
```

**Force pod to pull new image:**
```bash
kubectl rollout restart deployment/auth
kubectl rollout status deployment/auth
```

**Check which image pod is using:**
```bash
kubectl describe pod <pod-name> | grep Image:
```

### 4. MySQL Debugging

**Check MySQL status:**
```bash
sudo systemctl status mysql
sudo tail -f /var/log/mysql/error.log
```

**Check bind address:**
```bash
cat /etc/mysql/mysql.conf.d/mysqld.cnf | grep bind-address
```

**Check what's listening:**
```bash
ss -tlnp | grep 3306
# Should show: 0.0.0.0:3306 (not 127.0.0.1:3306)
```

**Check user permissions:**
```bash
sudo mysql -u root -e "SELECT User, Host FROM mysql.user WHERE User='auth_user';"
```

**Test connection:**
```bash
# From host
mysql -u auth_user -pAuth123 -h 192.168.49.1 auth -e "SELECT * FROM user;"

# From pod
kubectl exec -it deployment/auth -- mysql -u auth_user -pAuth123 -h 192.168.49.1 auth -e "SELECT * FROM user;"
```

### 5. Port Forwarding Management

**View active port forwards:**
```bash
ps aux | grep "kubectl port-forward"
```

**Stop specific port forward:**
```bash
pkill -f "kubectl port-forward.*gateway"
```

**Test port forward is working:**
```bash
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:80
```

## Common Issues and Solutions

### Issue 1: 404 NOT FOUND on /login Endpoint

**Symptom:**
```bash
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login
# Returns: 404 NOT FOUND
```

**Root Cause:** Deployed Docker image has buggy code (missing `@` decorator in route definition)

**Debugging Steps:**

1. **Check if service is running:**
   ```bash
   kubectl get pods -l app=auth
   # Should show: Running
   ```

2. **Test direct connection:**
   ```bash
   kubectl port-forward service/auth 5000:5000 &
   curl -X POST -u "dksahuji@gmail.com:Admin123" http://localhost:5000/login
   # Still 404? Not a gateway issue then!
   ```

3. **Inspect deployed code:**
   ```bash
   kubectl exec deployment/auth -- cat /app/server.py | grep -B 2 "def login"
   # Output: server.route("/login", method=["POST"])  ❌ Missing @!
   ```

4. **Compare with local code:**
   ```bash
   cat src/auth/server.py | grep -B 1 "def login"
   # Output: @server.route("/login", methods=["POST"])  ✅ Correct!
   ```

**Solution:**
```bash
# Rebuild Docker image
cd src/auth
docker build -t dksahuji/video2mp3-auth:latest .
docker push dksahuji/video2mp3-auth:latest

# Restart pods
kubectl rollout restart deployment/auth
kubectl rollout status deployment/auth

# Verify fix
kubectl exec deployment/auth -- grep -B 1 "def login" /app/server.py
# Should now show: @server.route("/login", methods=["POST"])
```

**Lesson Learned:** Always verify deployed code matches source code using `kubectl exec`. Docker images don't automatically update when you change local code!

### Issue 2: MySQL Connection Refused

**Symptom:**
```bash
# In pod logs:
kubectl logs -l app=auth --tail=50
# Shows: MySQLdb.OperationalError: (2002, "Can't connect to MySQL server on '192.168.49.1' (115)")
```

**Root Causes:**
- MySQL only listening on 127.0.0.1 (localhost)
- MySQL user only has localhost access

**Debugging Steps:**

1. **Check MySQL is running:**
   ```bash
   sudo systemctl status mysql
   # Should show: active (running)
   ```

2. **Check what MySQL is listening on:**
   ```bash
   ss -tlnp | grep 3306
   # Bad: LISTEN 0 151 127.0.0.1:3306 (only localhost)
   # Good: LISTEN 0 151 0.0.0.0:3306 (all interfaces)
   ```

3. **Test connectivity from pod:**
   ```bash
   kubectl exec deployment/auth -- nc -zv 192.168.49.1 3306
   # If connection refused: MySQL not accessible from minikube
   ```

4. **Check bind address:**
   ```bash
   cat /etc/mysql/mysql.conf.d/mysqld.cnf | grep bind-address
   # Output: bind-address = 127.0.0.1 ❌
   ```

**Solution Part A: Fix Bind Address**
```bash
# Backup config
sudo cp /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf.backup

# Change bind address
sudo sed -i 's/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

# Restart MySQL
sudo systemctl restart mysql

# Verify
ss -tlnp | grep 3306
# Should show: LISTEN 0 151 0.0.0.0:3306
```

**Test again:**
```bash
kubectl exec deployment/auth -- nc -zv 192.168.49.1 3306
# Now: Connection successful!

curl -X POST -u "dksahuji@gmail.com:Admin123" http://localhost:5000/login
# New error: Access denied for user 'auth_user'@'192.168.49.1'
```

5. **Check MySQL user permissions:**
   ```bash
   sudo mysql -u root -e "SELECT User, Host FROM mysql.user WHERE User='auth_user';"
   # Output: auth_user | localhost ❌
   # Problem: User only has localhost access, not 192.168.49.% access!
   ```

**Solution Part B: Grant Network Access**
```bash
sudo mysql -u root << 'EOF'
CREATE USER IF NOT EXISTS 'auth_user'@'192.168.49.%' IDENTIFIED BY 'Auth123';
GRANT ALL PRIVILEGES ON auth.* TO 'auth_user'@'192.168.49.%';
FLUSH PRIVILEGES;
SELECT User, Host FROM mysql.user WHERE User='auth_user';
EOF
```

**Verify:**
```bash
# Test from pod
kubectl exec -it deployment/auth -- mysql -u auth_user -pAuth123 -h 192.168.49.1 auth -e "SELECT * FROM user;"
# Should show user data

# Test login
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login
# Success! Returns JWT token
```

**Lesson Learned:**
- For Kubernetes pods to access host services, check both network layer (bind-address) and application layer (user permissions)
- Minikube pods connect from `192.168.49.x` network, not localhost
- Use `nc -zv` to test TCP connectivity before testing application-level connections

### Issue 3: Port 80 Forwarding with Sudo

**Symptom:** Want clean URLs without `:8080`, but `sudo kubectl port-forward` fails

**Problem A: Password Prompt in Background**
```bash
sudo kubectl port-forward service/gateway 80:8080 &
# Error: sudo: a password is required
```

**Root Cause:** Background processes can't prompt for passwords

**Solution:** Cache credentials first
```bash
sudo -v  # Prompts for password
sudo kubectl port-forward service/gateway 80:8080 > /tmp/gateway-pf.log 2>&1 &
```

**Problem B: Kubectl Can't Find Cluster**
```bash
cat /tmp/gateway-pf.log
# Error: couldn't get current server API group list: Get "http://localhost:8080/api": connection refused
```

**Debugging Steps:**

1. **Check user's kubectl works:**
   ```bash
   kubectl get service gateway
   # Works fine
   ```

2. **Check what root sees:**
   ```bash
   sudo kubectl config view --minify
   # Error or wrong API server address
   ```

3. **Why?** Check config file permissions:
   ```bash
   ls -la ~/.kube/config
   # Output: -rw------- 1 user user 827 (only user can read)
   ```

**Root Cause:** When using `sudo kubectl`:
- Runs as root
- Root looks for config in `/root/.kube/config` (doesn't exist)
- Falls back to default `localhost:8080` (old Kubernetes default)
- Even with `--kubeconfig=/home/user/.kube/config`, root can't read file (600 permissions)

**Solution:** Preserve user's environment
```bash
sudo -E env "PATH=$PATH" kubectl port-forward service/gateway 80:8080 > /tmp/gateway-pf.log 2>&1 &
```

**How it works:**
- `-E`: Preserves environment variables (including `HOME`)
- Root now looks in user's `$HOME/.kube/config`
- `env "PATH=$PATH"`: Ensures kubectl binary is found
- User's config file is readable because HOME still points to user's directory

**Verification:**
```bash
curl http://localhost:80/login
# Works!
```

**Problem C: Log File Permission Denied**
```bash
./start-services.sh
# Error: /tmp/auth-pf.log: Permission denied
```

**Debugging:**
```bash
ls -la /tmp/*-pf.log
# Output: -rw-r--r-- 1 root root 1234 (owned by root!)
```

**Root Cause:** Previous test runs created log files as root. Regular user can't overwrite them.

**Solution:** Clean up log files at script start
```bash
# In start-services.sh
sudo rm -f /tmp/gateway-pf.log /tmp/auth-pf.log /tmp/rabbitmq-pf.log 2>/dev/null
```

**Lesson Learned:**
- Background processes can't prompt for passwords (use `sudo -v` to cache)
- Root has different environment (HOME, PATH, config files)
- Use `sudo -E` to preserve user's environment
- Clean up artifacts from previous sudo runs to avoid permission issues

### Issue 4: Minikube Tunnel Shows Empty Services

**Symptom:**
```bash
minikube tunnel
# Output: services: []
```

**Debugging Steps:**

1. **What services exist?**
   ```bash
   kubectl get services --all-namespaces -o wide
   # All services are ClusterIP or NodePort
   ```

2. **Any LoadBalancer services?**
   ```bash
   kubectl get services -A | grep LoadBalancer
   # No output
   ```

**Root Cause:** `minikube tunnel` only works with LoadBalancer services. This project uses Ingress (nginx) for routing, not LoadBalancer.

**Solution:** Use port forwarding instead (see `./start-services.sh`)

**Lesson Learned:**
- `minikube tunnel` is for LoadBalancer services only
- Ingress is a different routing mechanism
- Port forwarding is simpler for local development

### Issue 5: Notification Service Deployment Fails with YAML Error

**Symptom:**
```bash
./deploy.sh
# Output:
Deploying notification service...
error: error parsing STDIN: error converting YAML to JSON: yaml: line 5: did not find expected key
```

**Debugging Steps:**

1. **Check the error details**
   ```bash
   # The error occurs when applying notification secret
   envsubst < src/notification/manifests/secret.yaml.template | kubectl apply -f -
   # Error: YAML parsing failed
   ```

2. **Inspect the generated YAML**
   ```bash
   # View what envsubst produces
   envsubst < src/notification/manifests/secret.yaml.template

   # Output shows:
   stringData:
     GMAIL_ADDRESS: ""your-email@gmail.com""  # Double quotes!
     GMAIL_PASSWORD: ""your-password""
   ```

3. **Check .env file format**
   ```bash
   cat .env
   # Found:
   GMAIL_ADDRESS="your-email@gmail.com"
   GMAIL_PASSWORD="your-16-char-password"
   ```

**Root Cause:**
- The `.env` file had quotes around values: `GMAIL_ADDRESS="value"`
- The template also has quotes: `GMAIL_ADDRESS: "${GMAIL_ADDRESS}"`
- When `envsubst` substitutes, it produces: `GMAIL_ADDRESS: ""value""` (double quotes)
- YAML parser fails on double-quoted values

**Solution:**
```bash
# Fix .env file - remove quotes around values
cat > .env << 'EOF'
GMAIL_ADDRESS=your-email@gmail.com
GMAIL_PASSWORD=your-16-char-app-password
EOF

# Now deploy works correctly
./deploy.sh
```

**Result:**
```yaml
# envsubst now produces valid YAML:
stringData:
  GMAIL_ADDRESS: "your-email@gmail.com"  # Single quotes (valid)
  GMAIL_PASSWORD: "your-16-char-password"
```

**Lesson Learned:**
- When using `envsubst` with templates that include quotes, DO NOT use quotes in `.env` files
- The template's quotes are sufficient: `"${VAR}"` becomes `"value"` (correct)
- With quotes in .env: `"${VAR}"` becomes `""value""` (incorrect)
- Always test the generated YAML: `envsubst < template.yaml | kubectl apply --dry-run=client -f -`

**Prevention:**
- Document .env format clearly in all READMEs
- Add validation to deploy.sh to check for quotes in .env
- Use `--dry-run=client` to catch YAML errors before applying

## Debugging Methodologies

### The Layered Debugging Approach

When debugging distributed systems, work from outside-in:

**Layer 1: Client/Network**
```bash
# Can I reach the endpoint at all?
curl -v http://localhost/login
ping 192.168.49.1
```

**Layer 2: Port Forwarding / Ingress**
```bash
# Is the port forward/ingress working?
ps aux | grep "kubectl port-forward"
kubectl get ingress
netstat -tlnp | grep :80
```

**Layer 3: Kubernetes Service**
```bash
# Does the service exist and have endpoints?
kubectl get service gateway
kubectl get endpoints gateway
```

**Layer 4: Pods**
```bash
# Are pods running and healthy?
kubectl get pods -l app=gateway
kubectl logs -l app=gateway --tail=50
kubectl describe pod <pod-name>
```

**Layer 5: Application Code**
```bash
# Is the code correct?
kubectl exec deployment/auth -- cat /app/server.py | grep "def login"
```

**Layer 6: Dependencies (DB, etc.)**
```bash
# Can the app reach its dependencies?
kubectl exec deployment/auth -- nc -zv 192.168.49.1 3306
```

### The Scientific Method for Debugging

1. **Observe** - What is the symptom?
2. **Hypothesize** - What could cause this?
3. **Test** - How can I verify my hypothesis?
4. **Analyze** - What do the results tell me?
5. **Repeat** - If hypothesis wrong, form new one

**Example:**
- **Observe:** Login returns 404
- **Hypothesize:** Maybe the route isn't registered
- **Test:** `kubectl exec deployment/auth -- python3 -c "from server import server; print(server.url_map)"`
- **Analyze:** Route missing from url_map
- **New Hypothesis:** Maybe code in pod is wrong
- **Test:** `kubectl exec deployment/auth -- cat /app/server.py | grep "def login"`
- **Analyze:** Found it! Missing `@` decorator

### Comparing Expected vs Actual

Always compare what you expect with what actually is:

```bash
# Expected: MySQL listening on all interfaces
# Actual: ss -tlnp | grep 3306
# Mismatch? Fix the bind-address

# Expected: User has access from 192.168.49.%
# Actual: SELECT User, Host FROM mysql.user;
# Mismatch? Grant permissions

# Expected: Deployed code has @server.route
# Actual: kubectl exec -- cat /app/server.py
# Mismatch? Rebuild Docker image
```

### Use Logs Effectively

**Stream logs in real-time:**
```bash
kubectl logs -l app=auth --tail=50 -f
```

**Grep for specific errors:**
```bash
kubectl logs -l app=auth --tail=1000 | grep -i error
kubectl logs -l app=auth --tail=1000 | grep -i mysql
```

**Check multiple sources:**
```bash
# Pod logs
kubectl logs <pod-name>

# Port forward logs
tail -f /tmp/gateway-pf.log

# MySQL logs
sudo tail -f /var/log/mysql/error.log

# System logs
journalctl -u mysql -f
```

## Lessons Learned

### 1. Docker Images Don't Auto-Update

**Problem:** Changed local code but deployed pods still had old code.

**Why:** Docker images are immutable. Changing local files doesn't change the image.

**Solution:**
```bash
docker build -t user/image:latest .
docker push user/image:latest
kubectl rollout restart deployment/name
```

**Prevention:** Always verify deployed code matches local code using `kubectl exec`.

### 2. Kubernetes Networking is Different from Local

**Problem:** Minikube pods can't connect to `localhost` on host machine.

**Why:** Each pod has its own network namespace. `localhost` in pod = the pod itself, not the host.

**Solution:** Use minikube gateway IP (`192.168.49.1`) to reach host services.

**Key Concepts:**
- Pods see host at: `192.168.49.1` (or `host.minikube.internal`)
- Services communicate via cluster DNS: `service-name:port`
- External access requires: Ingress, NodePort, LoadBalancer, or port forwarding

### 3. MySQL Bind Address Matters

**Problem:** MySQL running but pods can't connect.

**Why:** `bind-address = 127.0.0.1` means MySQL only listens on loopback interface.

**Solution:** Set `bind-address = 0.0.0.0` to listen on all interfaces.

**Security Note:** In production, use firewall rules to restrict access, not bind-address.

### 4. Privileged Ports Require Root

**Problem:** Can't bind to port 80 without sudo.

**Why:** Ports < 1024 are privileged on Linux.

**Solutions:**
- Use sudo (clean URLs, requires password)
- Use port >= 1024 (e.g., 8080, no sudo needed)
- Use `setcap` to grant capability (advanced)

### 5. Sudo Changes Environment

**Problem:** `sudo kubectl` can't find cluster config.

**Why:** Root has different HOME, PATH, and config locations.

**Solution:** Use `sudo -E env "PATH=$PATH"` to preserve environment.

**Understanding:**
- `-E`: Preserve environment variables
- `env "PATH=$PATH"`: Pass PATH explicitly
- Result: Root uses user's config and binaries

### 6. Port Forwarding vs Ingress

**Port Forwarding:**
- Direct tunnel: localhost → pod
- Bypasses Ingress
- Great for development
- Requires manual start/stop

**Ingress:**
- Production-like routing
- Based on hostname/path rules
- Requires Ingress controller
- More complex setup

**When to use:**
- Development: Port forwarding (simpler)
- Production-like testing: Ingress
- Load testing: Ingress (more realistic)

### 7. Always Check Logs

**Problem:** Command appears to succeed but doesn't work.

**Why:** Background processes (`&`) hide errors.

**Solution:** Always redirect to log file and check it:
```bash
command > /tmp/log.log 2>&1 &
sleep 1
cat /tmp/log.log  # Check for errors!
```

### 8. Verify Each Step

**Problem:** Multi-step fix didn't work, wasted time debugging wrong layer.

**Why:** Assumed earlier steps worked without verifying.

**Solution:** Test after each change:
```bash
# Fix bind-address
sudo systemctl restart mysql
ss -tlnp | grep 3306  # VERIFY before continuing

# Grant permissions
sudo mysql -e "GRANT..."
sudo mysql -e "SELECT User, Host..."  # VERIFY

# Test connectivity
kubectl exec deployment/auth -- nc -zv 192.168.49.1 3306  # VERIFY
```

## Additional Resources

- **Auth Service Issues:** See `src/auth/solution-auth-login.md`
- **Port Forwarding Details:** See `src/rabbitMQ/solution tunnel.md`
- **Quick Start Script:** `./start-services.sh` in project root

## Quick Troubleshooting Checklist

When something doesn't work:

- [ ] Are the pods running? `kubectl get pods`
- [ ] What do the logs say? `kubectl logs <pod-name>`
- [ ] Can I reach the service? `curl -v <url>`
- [ ] Is port forwarding running? `ps aux | grep port-forward`
- [ ] Does deployed code match local? `kubectl exec -- cat /app/file.py`
- [ ] Can pod reach dependencies? `kubectl exec -- nc -zv <host> <port>`
- [ ] Are permissions correct? `ls -la <file>` or `SELECT User, Host FROM mysql.user;`
- [ ] Did I check the logs? `tail -f /tmp/*.log`
- [ ] Did I verify each fix? Test after each change!

## Contributing

Found a new issue or debugging technique? Add it to this guide to help others!
