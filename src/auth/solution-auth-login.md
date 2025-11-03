# Auth Service Login Issue - Complete Solution

## Initial Problem
```bash
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login
# Result: 404 NOT FOUND or Connection Refused
```

## Root Cause Analysis

### Issue 1: Missing Route Decorator in Deployed Code

**Problem:** The `/login` route returned 404 because the deployed Docker image had buggy code.

**Investigation:**
```bash
kubectl exec deployment/auth -- cat /app/server.py | grep -B 2 "def login"
```

**Finding:** Line 17 in deployed code:
```python
server.route("/login", method=["POST"])  # ❌ WRONG - Missing @ and wrong parameter
def login():
```

**Should be:**
```python
@server.route("/login", methods=["POST"])  # ✅ CORRECT
def login():
```

**Two bugs:**
1. Missing `@` decorator symbol
2. Parameter name `method` instead of `methods` (plural)

**Fix:**
```bash
# 1. Verify local code is correct
cat src/auth/server.py | grep -B 1 "def login"

# 2. Rebuild Docker image
cd src/auth
docker build -t dksahuji/video2mp3-auth:latest .

# 3. Push to Docker Hub
docker push dksahuji/video2mp3-auth:latest

# 4. Restart pods to pull new image
kubectl rollout restart deployment/auth
kubectl rollout status deployment/auth
```

### Issue 2: MySQL Connection Refused from Minikube

**Problem:** After fixing the route, got MySQL connection error:
```
MySQLdb.OperationalError: (2002, "Can't connect to MySQL server on '192.168.49.1' (115)")
```

**Root Causes:**

#### A. MySQL Only Listening on Localhost
```bash
# Check MySQL bind address
cat /etc/mysql/mysql.conf.d/mysqld.cnf | grep bind-address
# Output: bind-address = 127.0.0.1  # ❌ Only localhost

ss -tlnp | grep 3306
# Output: LISTEN 0  151  127.0.0.1:3306  # ❌ Not accessible from 192.168.49.1
```

**Fix:**
```bash
# Backup config
sudo cp /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf.backup

# Change bind address to listen on all interfaces
sudo sed -i 's/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

# Restart MySQL
sudo systemctl restart mysql

# Verify
ss -tlnp | grep 3306
# Should show: LISTEN 0  151  0.0.0.0:3306
```

#### B. MySQL User Only Has Localhost Access

**Problem:** The `init.sql` creates user only for localhost:
```sql
CREATE USER 'auth_user'@'localhost' IDENTIFIED BY 'Auth123';
GRANT ALL PRIVILEGES ON auth.* TO 'auth_user'@'localhost';
```

But minikube pods connect from `192.168.49.1` (the minikube gateway IP).

**Fix:**
```bash
sudo mysql -u root << 'EOF'
CREATE USER IF NOT EXISTS 'auth_user'@'192.168.49.%' IDENTIFIED BY 'Auth123';
GRANT ALL PRIVILEGES ON auth.* TO 'auth_user'@'192.168.49.%';
FLUSH PRIVILEGES;
SELECT User, Host FROM mysql.user WHERE User='auth_user';
EOF
```

This grants access from the entire minikube network (`192.168.49.%`).

### Issue 3: Sudo Port Forwarding Environment Problems

**Problem:** When trying to use `sudo kubectl port-forward` for port 80, encountered multiple errors:

#### A. Password Prompt in Background Process
```bash
sudo kubectl port-forward service/gateway 80:8080 &
# Error: sudo: a password is required
```

**Root Cause:** Background processes (`&`) can't prompt for password interactively.

**Solution:** Cache sudo credentials first:
```bash
sudo -v  # Prompts for password and caches credentials
sudo kubectl port-forward service/gateway 80:8080 > /tmp/gateway-pf.log 2>&1 &
```

#### B. Kubectl Can't Connect to Cluster as Root
```bash
# Error in /tmp/gateway-pf.log:
E1103 14:31:01.404390 kubectl memcache.go:265 couldn't get current server API group list:
Get "http://localhost:8080/api?timeout=32s": dial tcp 127.0.0.1:8080: connect: connection refused
```

**Root Cause:** When using `sudo kubectl`, it runs as root which doesn't have access to user's `~/.kube/config`. Root looks for config in `/root/.kube/config` (doesn't exist) and falls back to trying `localhost:8080` (old default).

**Debugging Steps:**
```bash
# 1. Verify user's kubectl works
kubectl get service gateway
# Works: 8080

# 2. Try with explicit kubeconfig path
sudo kubectl --kubeconfig=/home/user/.kube/config get service gateway
# Still fails: root can't read file with 600 permissions

# 3. Check file permissions
ls -la ~/.kube/config
# -rw------- 1 user user 827 Nov 3 13:30 /home/user/.kube/config
```

**Solution:** Use `sudo -E` to preserve environment variables:
```bash
sudo -E env "PATH=$PATH" kubectl port-forward service/gateway 80:8080 > /tmp/gateway-pf.log 2>&1 &
```

**How it works:**
- `-E`: Preserves environment variables (including `HOME` which points to user's home directory)
- `env "PATH=$PATH"`: Ensures kubectl binary can be found
- Result: Root uses user's `~/.kube/config` successfully

#### C. Log File Permission Denied
```bash
./start-services.sh: line 27: /tmp/auth-pf.log: Permission denied
```

**Root Cause:** Previous test runs created log files owned by root. Regular user can't overwrite them.

**Debugging:**
```bash
ls -la /tmp/*-pf.log
# -rw-r--r-- 1 root root 1234 Nov 3 14:31 /tmp/gateway-pf.log
```

**Solution:** Clean up log files at script start:
```bash
sudo rm -f /tmp/gateway-pf.log /tmp/auth-pf.log /tmp/rabbitmq-pf.log 2>/dev/null
```

## Solution Options

### Option 1: Use Port 80 Forwarding (RECOMMENDED - Clean URLs)

**Why this is recommended:**
- Clean URLs exactly like tutorial: `http://video2mp3.com/login`
- No port numbers needed
- One-time sudo password prompt
- Works with localhost

**Setup - Use the provided script (easiest):**
```bash
# From project root (will prompt for sudo password)
./start-services.sh
```

**Or manually:**
```bash
# Gateway on port 80 (requires sudo)
sudo kubectl port-forward service/gateway 80:8080 > /tmp/gateway-pf.log 2>&1 &

# Auth service (port 5000)
kubectl port-forward service/auth 5000:5000 > /tmp/auth-pf.log 2>&1 &

# RabbitMQ (port 15672)
kubectl port-forward pod/rabbitmq-0 15672:15672 > /tmp/rabbitmq-pf.log 2>&1 &
```

**Usage (exact command from tutorial!):**
```bash
# Clean URL - no port number!
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login

# Also works with localhost
curl -X POST -u "dksahuji@gmail.com:Admin123" http://localhost/login
```

**Expected Response:**
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Stop all services:**
```bash
sudo pkill -f 'kubectl port-forward'
```

### Option 2: Use Port 8080 Forwarding (No sudo needed)

**Use if you can't/don't want to use sudo:**
```bash
# Gateway on port 8080
kubectl port-forward service/gateway 8080:8080 > /tmp/gateway-pf.log 2>&1 &

# Auth and RabbitMQ
kubectl port-forward service/auth 5000:5000 > /tmp/auth-pf.log 2>&1 &
kubectl port-forward pod/rabbitmq-0 15672:15672 > /tmp/rabbitmq-pf.log 2>&1 &
```

**Usage (add :8080 to URL):**
```bash
curl -X POST -u "dksahuji@gmail.com:Admin123" http://localhost:8080/login
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com:8080/login
```

### Option 3: Use Ingress with Minikube IP

**Setup:**
```bash
# Update /etc/hosts to point to minikube IP (one time)
sudo sed -i 's/127.0.0.1 video2mp3.com/192.168.49.2 video2mp3.com/' /etc/hosts
```

**Usage:**
```bash
# Works without port forwarding
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login
```

**Note:** Changes your hosts file, requires ingress to be running

## Traffic Flow Diagram

### With Port 80 Forwarding (Recommended):
```
curl request to video2mp3.com/login (no port!)
    ↓
/etc/hosts resolves to 127.0.0.1
    ↓
kubectl port-forward (listening on localhost:80)
    ↓
gateway service:8080 (in cluster)
    ↓
auth service:5000 (in cluster)
    ↓
MySQL (192.168.49.1:3306)
    ↓
Returns JWT token
```

## Verification Steps

### 1. Check Route is Fixed
```bash
kubectl exec deployment/auth -- grep -B 1 "def login" /app/server.py
# Should show: @server.route("/login", methods=["POST"])
```

### 2. Check MySQL Connectivity
```bash
# From your host
mysql -u auth_user -pAuth123 -h 192.168.49.1 auth -e "SELECT * FROM user;"

# From inside auth pod
kubectl exec -it deployment/auth -- mysql -u auth_user -pAuth123 -h 192.168.49.1 auth -e "SELECT * FROM user;"
```

### 3. Test Login
```bash
# Test and save token (clean URL!)
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login > token.txt

# Validate token
curl -X POST -H "Authorization: Bearer $(cat token.txt)" http://localhost:5000/validate

# Cleanup
rm token.txt
```

## Port Forward Management

### View Active Port Forwards
```bash
ps aux | grep "kubectl port-forward"
```

### Stop Port Forwards
```bash
# Stop all port forwards (sudo needed since gateway uses port 80)
sudo pkill -f 'kubectl port-forward'

# Or stop individually
sudo pkill -f 'kubectl port-forward.*gateway'
pkill -f 'kubectl port-forward.*auth'
pkill -f 'kubectl port-forward.*rabbitmq'
```

### Quick Start - Use Provided Script

The easiest way is to use the provided startup script:

```bash
# From project root (will prompt for sudo password)
./start-services.sh
```

This script:
- Starts gateway (port 80), auth (5000), and RabbitMQ (15672)
- Shows URLs and PIDs for each service
- Provides test commands
- Uses clean URLs without port numbers

## Key Takeaways

1. **Docker Image Issues:** Always verify deployed code matches your local source code
   - Use `kubectl exec` to inspect running containers
   - Rebuild and push images after code changes

2. **MySQL Networking:** For minikube/Kubernetes to access host MySQL:
   - Change `bind-address` to `0.0.0.0` in MySQL config
   - Grant access from minikube network: `'user'@'192.168.49.%'`
   - Restart MySQL after config changes

3. **Port Forwarding Approach (Recommended):**
   - Use port 80 for gateway (clean URLs, requires sudo)
   - Works with `/etc/hosts` pointing to `127.0.0.1`
   - Use provided `start-services.sh` script for convenience
   - Clean URLs exactly like tutorial: `http://video2mp3.com/login`

4. **Minikube Host Access:**
   - Minikube sees host machine at `192.168.49.1`
   - Use this IP for services running on host (MySQL, MongoDB, etc.)
   - ConfigMap should have: `MYSQL_HOST: 192.168.49.1`

5. **Quick Start:**
   - Run `./start-services.sh` to start all services (will prompt for sudo password)
   - Test with: `curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login`
   - Stop with: `sudo pkill -f 'kubectl port-forward'`

## Debugging Methodology: How We Found These Issues

This section documents the systematic debugging approach used to identify and fix all issues.

### 1. Debugging the 404 Error

**Symptom:** `curl` returns 404 NOT FOUND for `/login` endpoint

**Step 1: Verify the service is running**
```bash
# Check if auth pods are running
kubectl get pods -l app=auth
# Output: Running

# Check if service exists
kubectl get service auth
# Output: Service exists on port 5000
```

**Step 2: Test direct connection to auth service**
```bash
# Port forward to auth directly
kubectl port-forward service/auth 5000:5000 &

# Test the endpoint
curl -X POST -u "dksahuji@gmail.com:Admin123" http://localhost:5000/login
# Result: Still 404 - so it's not a gateway issue
```

**Step 3: Check what routes are registered**
```bash
# Try to see registered routes
kubectl exec deployment/auth -- python3 -c "from server import server; print(server.url_map)"
# Shows available routes but /login might not be there
```

**Step 4: Inspect the actual deployed code**
```bash
# Look at the deployed server.py file
kubectl exec deployment/auth -- cat /app/server.py | grep -B 2 "def login"
# Output: server.route("/login", method=["POST"])  # ❌ Missing @!
```

**Finding:** The deployed code has a bug - missing `@` decorator!

**Step 5: Compare with local source**
```bash
# Check local code
cat src/auth/server.py | grep -B 1 "def login"
# Output: @server.route("/login", methods=["POST"])  # ✅ Correct!
```

**Conclusion:** Docker image is outdated. Need to rebuild and push.

**Learning:** When you get unexpected behavior, always verify the deployed code matches your source code using `kubectl exec`.

### 2. Debugging MySQL Connection Refused

**Symptom:** After fixing route decorator, got new error in pod logs:
```
MySQLdb.OperationalError: (2002, "Can't connect to MySQL server on '192.168.49.1' (115)")
```

**Step 1: Check pod logs for details**
```bash
kubectl logs -l app=auth --tail=50
# Shows MySQL connection error with IP 192.168.49.1
```

**Step 2: Verify MySQL is running on host**
```bash
sudo systemctl status mysql
# Output: active (running)

ss -tlnp | grep 3306
# Output: LISTEN 0 151 127.0.0.1:3306
```

**Finding:** MySQL only listening on 127.0.0.1, not on 192.168.49.1!

**Step 3: Test connectivity from pod**
```bash
# Use netcat to test TCP connection
kubectl exec deployment/auth -- nc -zv 192.168.49.1 3306
# Output: Connection refused
```

**Step 4: Check MySQL bind-address configuration**
```bash
cat /etc/mysql/mysql.conf.d/mysqld.cnf | grep bind-address
# Output: bind-address = 127.0.0.1
```

**Solution A:** Change bind-address to 0.0.0.0 and restart MySQL

**Step 5: Test again after bind-address change**
```bash
kubectl exec deployment/auth -- nc -zv 192.168.49.1 3306
# Output: Connection successful!

# Try curl again
curl -X POST -u "dksahuji@gmail.com:Admin123" http://localhost:5000/login
# New error: Access denied for user 'auth_user'@'192.168.49.1'
```

**Finding:** MySQL user only has localhost access, not 192.168.49.% access!

**Step 6: Check MySQL user permissions**
```bash
sudo mysql -u root -e "SELECT User, Host FROM mysql.user WHERE User='auth_user';"
# Output: auth_user | localhost
```

**Solution B:** Grant access from minikube network (192.168.49.%)

**Learning:** For Kubernetes connectivity:
1. Check if service is running
2. Check if service is listening on correct interface (0.0.0.0 vs 127.0.0.1)
3. Use `netcat` (`nc -zv`) to test TCP connectivity
4. Check application-level permissions (MySQL users, firewall rules)

### 3. Debugging Sudo Port Forwarding

**Symptom:** Want clean URLs without `:8080`, but `sudo kubectl port-forward` fails

**Attempt 1: Direct sudo with background**
```bash
sudo kubectl port-forward service/gateway 80:8080 &
# Error: sudo: a password is required
```

**Finding:** Can't prompt for password in background process

**Solution:** Cache credentials with `sudo -v` first

**Attempt 2: With cached credentials**
```bash
sudo -v
sudo kubectl port-forward service/gateway 80:8080 > /tmp/test.log 2>&1 &
sleep 2
cat /tmp/test.log
# Error: couldn't get current server API group list: Get "http://localhost:8080/api?timeout=32s": connect: connection refused
```

**Finding:** kubectl trying to connect to localhost:8080 (wrong API server address)

**Step 1: Check why kubectl looks for wrong API server**
```bash
# As user
kubectl config view --minify
# Shows: server: https://192.168.49.2:8443

# What does root see?
sudo kubectl config view --minify
# Error or shows localhost:8080 (default when no config found)
```

**Finding:** Root doesn't have access to user's kubectl config

**Step 2: Check kubeconfig file location and permissions**
```bash
ls -la ~/.kube/config
# Output: -rw------- 1 user user 827 (only user can read)

# Try explicit path
sudo kubectl --kubeconfig=/home/user/.kube/config get service gateway
# Still fails - root can't read file with 600 permissions
```

**Step 3: Try preserving environment**
```bash
sudo -E kubectl get service gateway
# Fails: kubectl not in root's PATH

sudo -E env "PATH=$PATH" kubectl get service gateway
# Works! Shows gateway service
```

**Solution:** Use `sudo -E env "PATH=$PATH"` to preserve both HOME (for kubeconfig) and PATH (for kubectl binary)

**Verification:**
```bash
sudo -E env "PATH=$PATH" kubectl port-forward service/gateway 80:8080 &
curl http://localhost:80/login
# Success!
```

**Learning:** When using `sudo`:
1. Background processes can't prompt for passwords (use `sudo -v` to cache)
2. Root has different environment (HOME, PATH, config files)
3. Use `sudo -E` to preserve user's environment variables
4. Check log files for actual error messages (don't assume the command worked)

### 4. Debugging Permission Denied Errors

**Symptom:** Script fails with "Permission denied" for log files

```bash
./start-services.sh: line 27: /tmp/auth-pf.log: Permission denied
```

**Step 1: Check who owns the log files**
```bash
ls -la /tmp/*-pf.log
# Output: -rw-r--r-- 1 root root 1234 Nov 3 14:31 /tmp/gateway-pf.log
```

**Finding:** Log files owned by root from previous test runs

**Step 2: Try to remove as user**
```bash
rm /tmp/gateway-pf.log
# Error: Permission denied
```

**Solution:** Clean up log files with sudo at script start

**Learning:** When testing with sudo, always clean up artifacts that might have different ownership

## Troubleshooting

### Still Getting 404?
```bash
# Check if pods are running
kubectl get pods -l app=auth

# Check pod logs
kubectl logs -l app=auth --tail=50

# Check route is registered
kubectl exec deployment/auth -- python3 -c "from server import server; print(server.url_map)"
```

### MySQL Connection Issues?
```bash
# Test from host
nc -zv 192.168.49.1 3306

# Test from pod
kubectl exec deployment/auth -- nc -zv 192.168.49.1 3306

# Check MySQL logs
sudo tail -f /var/log/mysql/error.log
```

### Port Forward Not Working?
```bash
# Check if port is in use
netstat -tlnp | grep :8080

# Check port forward logs
tail -f /tmp/gateway-pf.log

# Restart port forward
pkill -f "kubectl port-forward.*gateway"
kubectl port-forward service/gateway 8080:8080
```

## Related Documentation

- See `solution tunnel.md` in `../rabbitMQ/` for general port forwarding concepts
- See `README.md` for initial setup instructions
- See `init.sql` for database schema
