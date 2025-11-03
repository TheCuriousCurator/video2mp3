# Video2MP3 System - Complete Demo Tutorial

## Table of Contents
1. [System Overview](#system-overview)
2. [Architecture Deep Dive](#architecture-deep-dive)
3. [Prerequisites](#prerequisites)
4. [Complete Demo Walkthrough](#complete-demo-walkthrough)
5. [MySQL Database Operations](#mysql-database-operations)
6. [MongoDB Database Operations](#mongodb-database-operations)
7. [RabbitMQ Queue Management](#rabbitmq-queue-management)
8. [Monitoring & Debugging](#monitoring--debugging)
9. [API Reference](#api-reference)
10. [Troubleshooting Guide](#troubleshooting-guide)

---

## System Overview

The Video2MP3 system is a production-ready microservices architecture that converts video files to MP3 audio format using asynchronous message processing. The system demonstrates real-world patterns including:

- **Microservices Architecture**: Independently deployable services
- **Asynchronous Processing**: RabbitMQ message queuing
- **JWT Authentication**: Secure token-based auth
- **Container Orchestration**: Kubernetes (minikube)
- **GridFS Storage**: Large file handling in MongoDB
- **Worker Scaling**: Horizontal scaling for high throughput

---

## Architecture Deep Dive

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         CLIENT                               │
│            (curl / Browser / Mobile App)                     │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTP Request (JWT Token)
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                      GATEWAY SERVICE                         │
│                   (Flask, Port 8080)                         │
│  - Login Proxy                                               │
│  - JWT Validation                                            │
│  - Video Upload                                              │
│  - MP3 Download                                              │
└────┬──────────────┬─────────────┬──────────────┬────────────┘
     │              │             │              │
     │(login)       │(validate)   │(store)       │(queue)
     ↓              │             ↓              ↓
┌─────────────┐     │      ┌─────────────┐  ┌─────────────┐
│AUTH SERVICE │     │      │  MongoDB    │  │  RabbitMQ   │
│(Flask:5000) │     │      │(Host:27017) │  │(StatefulSet)│
│             │     │      │             │  │             │
│- JWT Gen    │◀────┘      │- GridFS     │  │- video queue│
│- JWT Valid  │            │  Videos     │  │- mp3 queue  │
│             │            │- GridFS MP3s│  │             │
└─────┬───────┘            └─────────────┘  └──────┬──────┘
      │                                            │
      │ MySQL Query                                │ Consume
      ↓                                            ↓
┌─────────────┐                          ┌─────────────────┐
│   MySQL     │                          │   CONVERTER     │
│(Host:3306)  │                          │   (4 Workers)   │
│             │                          │                 │
│- auth DB    │                          │- FFmpeg         │
│- user table │                          │- MoviePy        │
└─────────────┘                          │- Video→MP3      │
                                         └────────┬────────┘
                                                  │
                                                  │ Store MP3
                                                  ↓
                                         ┌─────────────────┐
                                         │   MongoDB       │
                                         │  (GridFS MP3)   │
                                         └────────┬────────┘
                                                  │
                                         Publish to mp3 queue
                                                  ↓
                                         ┌─────────────────┐
                                         │   RabbitMQ      │
                                         │   mp3 queue     │
                                         └────────┬────────┘
                                                  │ Consume
                                                  ↓
                                         ┌─────────────────┐
                                         │  NOTIFICATION   │
                                         │   (4 Workers)   │
                                         │                 │
                                         │- Gmail SMTP     │
                                         │- Send Email     │
                                         └────────┬────────┘
                                                  │
                                                  ↓
                                         ┌─────────────────┐
                                         │   User Email    │
                                         │                 │
                                         │ Subject:        │
                                         │ "MP3 Download"  │
                                         │                 │
                                         │ Body:           │
                                         │ "mp3 file_id:   │
                                         │  <ObjectId> is  │
                                         │  now ready!"    │
                                         └─────────────────┘
```

### Service Breakdown

| Service | Language | Port | Replicas | Purpose |
|---------|----------|------|----------|---------|
| **Gateway** | Flask | 8080 | 2 | API entry point, file handling |
| **Auth** | Flask | 5000 | 2 | JWT authentication and validation |
| **Converter** | Python | N/A | 4 | Video-to-MP3 conversion workers |
| **Notification** | Python | N/A | 4 | Email notification workers |
| **RabbitMQ** | Erlang | 5672, 15672 | 1 (StatefulSet) | Message queue broker |
| **MySQL** | SQL | 3306 | Host | User authentication database |
| **MongoDB** | NoSQL | 27017 | Host | Video/MP3 file storage (GridFS) |

### Data Flow

**Upload Flow:**
```
1. Client → Gateway:login → Auth:5000 → MySQL → JWT Token
2. Client → Gateway:upload (+ JWT)
3. Gateway → Auth:validate (JWT)
4. Gateway → MongoDB (store video via GridFS) → video_fid
5. Gateway → RabbitMQ (publish to "video" queue)
6. Converter → RabbitMQ (consume from "video" queue)
7. Converter → MongoDB (retrieve video by video_fid)
8. Converter → FFmpeg (extract audio)
9. Converter → MongoDB (store MP3 via GridFS) → mp3_fid
10. Converter → RabbitMQ (publish to "mp3" queue)
11. Notification → RabbitMQ (consume from "mp3" queue)
12. Notification → Gmail SMTP (send email with mp3_fid)
```

**Download Flow:**
```
1. Client → Gateway:download (+ JWT + fid)
2. Gateway → Auth:validate (JWT)
3. Gateway → MongoDB (retrieve MP3 by fid)
4. Gateway → Client (stream MP3 file)
```

---

## Prerequisites

### System Requirements
- **Kubernetes**: minikube running
- **kubectl**: Configured for minikube cluster
- **MySQL**: 8.0 running on host machine (port 3306)
- **MongoDB**: Running on host machine (port 27017)
- **Docker**: For building images (optional)

### Networking Setup
```bash
# Add hostname to /etc/hosts
echo "127.0.0.1 video2mp3.com" | sudo tee -a /etc/hosts

# Verify
ping -c 1 video2mp3.com
```

### Host Database Configuration
Run this ONCE before first deployment:
```bash
./setup-host.sh
```

This configures MySQL and MongoDB to accept connections from minikube pods (192.168.49.%).

---

## Complete Demo Walkthrough

The `run-demo.sh` script performs a complete end-to-end demonstration of the system. You can run it directly:

```bash
./run-demo.sh
```

Or follow along manually with the steps below.

### Step 1: Clean Slate - Undeploy Existing Services

```bash
./undeploy.sh
```

**What it does:**
- Stops all kubectl port-forward processes
- Deletes all deployments: auth, gateway, converter, notification
- Deletes all services: auth, gateway, rabbitmq
- Deletes all configmaps and secrets
- Deletes RabbitMQ StatefulSet and PersistentVolumeClaim
- Deletes Ingress resources

**Expected output:**
```
Stopping all port forwards...
Deleting deployments...
deployment.apps "auth" deleted
deployment.apps "gateway" deleted
deployment.apps "converter" deleted
deployment.apps "notification" deleted
...
```

**Verify:**
```bash
kubectl get all
# Should show: No resources found in default namespace
```

---

### Step 2: Deploy All Services

```bash
./deploy.sh
```

**What it does:**
1. Auto-detects minikube IP (e.g., 192.168.49.2)
2. Calculates host IP (e.g., 192.168.49.1)
3. Uses `envsubst` to replace `${MYSQL_HOST}` and `${MONGODB_HOST}` in template files
4. Deploys services in order:
   - RabbitMQ (StatefulSet with PVC)
   - Auth service (with MySQL connection)
   - Gateway service (with MongoDB and RabbitMQ connections)
   - Converter workers (4 replicas)
   - Notification workers (4 replicas with Gmail credentials)
5. Waits for all deployments to be ready

**Deployment order matters:**
- RabbitMQ must be running before converter/notification
- Auth must be running before gateway can validate tokens

**Expected output:**
```
Deploying to Kubernetes...
Host IP: 192.168.49.1

Deploying RabbitMQ...
statefulset.apps/rabbitmq created
service/rabbitmq created

Deploying Auth Service...
configmap/auth-configmap created
deployment.apps/auth created
...

Waiting for deployments to be ready...
deployment "auth" successfully rolled out
deployment "gateway" successfully rolled out
deployment "converter" successfully rolled out
deployment "notification" successfully rolled out

Deployment complete!
```

**Verify deployment:**
```bash
# Check all pods are running
kubectl get pods

# Expected output:
NAME                           READY   STATUS    RESTARTS   AGE
auth-xxxxxxxxx-xxxxx           1/1     Running   0          30s
gateway-xxxxxxxxx-xxxxx        1/1     Running   0          30s
converter-xxxxxxxxx-xxxxx      1/1     Running   0          30s
converter-xxxxxxxxx-yyyyy      1/1     Running   0          30s
converter-xxxxxxxxx-zzzzz      1/1     Running   0          30s
converter-xxxxxxxxx-aaaaa      1/1     Running   0          30s
notification-xxxxxxxxx-xxxxx   1/1     Running   0          30s
notification-xxxxxxxxx-yyyyy   1/1     Running   0          30s
notification-xxxxxxxxx-zzzzz   1/1     Running   0          30s
notification-xxxxxxxxx-aaaaa   1/1     Running   0          30s
rabbitmq-0                     1/1     Running   0          30s

# Check services
kubectl get svc

# Expected output:
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)              AGE
auth         ClusterIP   10.96.xxx.xxx   <none>        5000/TCP             30s
gateway      ClusterIP   10.96.xxx.xxx   <none>        8080/TCP             30s
rabbitmq     ClusterIP   10.96.xxx.xxx   <none>        5672/TCP,15672/TCP   30s
```

**Verify configuration:**
```bash
# Check auth service knows MySQL host
kubectl get configmap auth-configmap -o yaml | grep MYSQL_HOST
# Expected: MYSQL_HOST: "192.168.49.1"

# Check gateway service knows MongoDB host
kubectl get configmap gateway-configmap -o yaml | grep MONGODB_HOST
# Expected: MONGODB_HOST: "192.168.49.1"
```

---

### Step 3: Start Port Forwarding

```bash
./start-services.sh
```

**What it does:**
- Stops any existing port forwards
- Cleans up old log files
- Prompts for sudo password (for port 80 forwarding)
- Starts port forwarding in background:
  - Gateway: localhost:80 → gateway:8080
  - Auth: localhost:5000 → auth:5000
  - RabbitMQ Management: localhost:15672 → rabbitmq:15672
- Logs output to `/tmp/{service}-pf.log`

**Expected output:**
```
Starting port forwarding for video2mp3 services...
[sudo] password for user:

Cleaning up old log files...
Starting port forwards in background...

✓ Gateway:   http://video2mp3.com (localhost:80 → gateway:8080)
  Log:       tail -f /tmp/gateway-pf.log
  PID:       12345

✓ Auth:      http://localhost:5000 (→ auth:5000)
  Log:       tail -f /tmp/auth-pf.log
  PID:       12346

✓ RabbitMQ:  http://localhost:15672 (→ rabbitmq:15672)
  Log:       tail -f /tmp/rabbitmq-pf.log
  PID:       12347

Port forwarding started! Use these URLs:
  - Gateway:   http://video2mp3.com
  - Auth:      http://localhost:5000
  - RabbitMQ:  http://localhost:15672 (guest/guest)

To stop all port forwards:
  sudo pkill -f 'kubectl port-forward'
```

**Verify port forwards are running:**
```bash
# Check processes
ps aux | grep "kubectl port-forward"

# Expected: 3 processes (gateway, auth, rabbitmq)

# Test connectivity
curl -s -o /dev/null -w "%{http_code}" http://localhost:5000
# Expected: 405 (Method Not Allowed - means service is reachable)
```

---

### Step 4: Login and Get JWT Token

```bash
rm -f token.txt
TOKEN=$(curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login 2>/dev/null)
echo ""
echo "Token saved to token.txt"
```

**Note:** The script stores the token in the `$TOKEN` environment variable for immediate use in subsequent commands.

**What happens internally:**

1. **Client sends Basic Auth**:
   ```
   Authorization: Basic ZGtzYWh1amlAZ21haWwuY29tOkFkbWluMTIz
   ```
   (Base64 encoded `dksahuji@gmail.com:Admin123`)

2. **Gateway receives request** at `/login` endpoint

3. **Gateway proxies to Auth service**:
   ```python
   # gateway/auth_svc/access.py
   response = requests.post(
       f"http://{AUTH_SVC_ADDRESS}/login",
       headers=request.headers
   )
   ```

4. **Auth service validates credentials**:
   ```python
   # auth/server.py
   username, password = auth.username, auth.password

   # Query MySQL
   cur = mysql.connection.cursor()
   res = cur.execute(
       "SELECT email, password FROM user WHERE email=%s", (username,)
   )

   if res > 0:
       user_row = cur.fetchone()
       email = user_row[0]
       hashed_password = user_row[1]

       if email == username and hashed_password == password:
           # Generate JWT token
           return jwt.encode(
               {
                   "username": username,
                   "exp": datetime.datetime.utcnow() + datetime.timedelta(days=1)
               },
               os.environ.get("JWT_SECRET"),
               algorithm="HS256"
           )
   ```

5. **MySQL query executes**:
   ```sql
   SELECT email, password FROM user WHERE email='dksahuji@gmail.com';
   ```

6. **JWT token is generated** with:
   - Payload: `{"username": "dksahuji@gmail.com", "exp": <timestamp>}`
   - Secret: From environment variable `JWT_SECRET`
   - Algorithm: HS256

7. **Token is returned to client**

**Example token:**
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImRrc2FodWppQGdtYWlsLmNvbSIsImV4cCI6MTczMDc5MjAwMH0.xxx
```

**Decode token to see payload:**
```bash
# Decode at https://jwt.io or use Python
echo $TOKEN

# Or decode with Python
python3 << EOF
import base64, json, os
token = os.environ.get('TOKEN', '')
if token:
    payload = token.split('.')[1]
    # Add padding if needed
    payload += '=' * (4 - len(payload) % 4)
    decoded = base64.urlsafe_b64decode(payload)
    print(json.dumps(json.loads(decoded), indent=2))
else:
    print("TOKEN environment variable not set")
EOF
```

**Expected payload:**
```json
{
  "username": "dksahuji@gmail.com",
  "exp": 1730792000
}
```

**Verify token:**
```bash
# Check token was saved
echo $TOKEN
# Should show JWT token string

# Token should work for authentication
curl -H "Authorization: Bearer $TOKEN" http://video2mp3.com/upload
# Should NOT return 401 (may return 400 if no file provided, but that's OK)
```

---

### Step 5: Upload Video File

```bash
curl -X POST -F 'file=@./agentic_ai-using-external-feedback.mp4' -H "Authorization: Bearer $TOKEN" http://video2mp3.com/upload
```

**What happens internally:**

1. **Gateway validates JWT token**:
   ```python
   # gateway/auth/validate.py
   response = requests.post(
       f"http://{AUTH_SVC_ADDRESS}/validate",
       headers={"Authorization": request.headers["Authorization"]}
   )
   ```

2. **Auth service validates token**:
   ```python
   # auth/server.py @server.route("/validate")
   token = request.headers["Authorization"].split(" ")[1]
   try:
       jwt.decode(token, os.environ.get("JWT_SECRET"), algorithms=["HS256"])
       return "", 200  # Valid token
   except:
       return "", 401  # Invalid token
   ```

3. **Gateway stores video in MongoDB GridFS**:
   ```python
   # gateway/storage/util.py
   video_fid = fs_videos.put(f)  # Returns ObjectId
   ```
   - File is chunked into 255KB pieces
   - Stored in `videos.fs.files` (metadata) and `videos.fs.chunks` (data)

4. **Gateway publishes message to RabbitMQ**:
   ```python
   message = {
       "video_fid": str(video_fid),
       "mp3_fid": None,
       "username": access["username"]
   }
   channel.basic_publish(
       exchange="",
       routing_key="video",
       body=json.dumps(message)
   )
   ```

5. **Converter worker consumes message**:
   - One of 4 converter workers picks up the message
   - Downloads video from MongoDB by `video_fid`
   - Saves to temporary file: `/tmp/<video_fid>.mp4`

6. **FFmpeg extracts audio**:
   ```python
   # converter/convert/to_mp3.py
   from moviepy.editor import VideoFileClip

   video = VideoFileClip(temp_video_path)
   audio = video.audio
   audio.write_audiofile(temp_mp3_path)
   ```
   - MoviePy uses FFmpeg under the hood
   - Extracts audio track and encodes as MP3

7. **Converter stores MP3 in MongoDB**:
   ```python
   mp3_fid = fs_mp3s.put(mp3_file)  # Returns ObjectId
   ```

8. **Converter publishes to mp3 queue**:
   ```python
   message = {
       "video_fid": str(video_fid),
       "mp3_fid": str(mp3_fid),
       "username": username
   }
   channel.basic_publish(
       exchange="",
       routing_key="mp3",
       body=json.dumps(message)
   )
   ```

9. **Notification worker consumes message**:
   - One of 4 notification workers picks up the message

10. **Email is sent via Gmail SMTP**:
    ```python
    # notification/send/email.py
    msg = EmailMessage()
    msg["Subject"] = "MP3 Download"
    msg["From"] = gmail_address
    msg["To"] = username
    msg.set_content(f"mp3 file_id: {mp3_fid} is now ready!")

    session = smtplib.SMTP("smtp.gmail.com", 587)
    session.starttls()
    session.login(gmail_address, gmail_password)
    session.send_message(msg)
    ```

**Expected response:**
```
success!
```

**Demo Complete!**

After the upload completes, the script outputs what happens next:

```
==========================================
Demo Complete!
==========================================

What happens next:
  1. Converter workers are processing the video → MP3
  2. When complete, notification service will send email to: dksahuji@gmail.com
  3. Email subject: 'MP3 Download'
  4. Email body: 'mp3 file_id: <ObjectId> is now ready!'

Monitor progress:
  kubectl logs -l app=converter -f    # Watch conversion
  kubectl logs -l app=notification -f # Watch email sending

Check your email inbox for the notification!
```

**What to monitor:**
```bash
# Watch converter process video
kubectl logs -l app=converter -f

# Expected output:
Waiting for messages...
Received message: {"video_fid": "...", "mp3_fid": null, "username": "dksahuji@gmail.com"}
Downloading video from MongoDB...
Converting video to MP3...
Uploading MP3 to MongoDB...
Publishing to mp3 queue...
Conversion complete!

# Watch notification send email
kubectl logs -l app=notification -f

# Expected output:
Waiting for messages...
Received message: {"video_fid": "...", "mp3_fid": "...", "username": "dksahuji@gmail.com"}
Sending email to: dksahuji@gmail.com
Email sent successfully!
```

---

### Step 6: Download MP3 File (After Receiving Email)

**Email notification:**
- **To**: dksahuji@gmail.com
- **Subject**: MP3 Download
- **Body**: `mp3 file_id: 6908d08362046551e1ec6efa is now ready!`

**Download the MP3:**

Replace `<file_id>` with the ObjectId from your email notification:

```bash
curl --output mp3_download.mp3 -X GET \
  -H "Authorization: Bearer $TOKEN" \
  "http://video2mp3.com/download?fid=<file_id>"
```

**Example:**
```bash
curl --output mp3_download.mp3 -X GET \
  -H "Authorization: Bearer $TOKEN" \
  "http://video2mp3.com/download?fid=6908d08362046551e1ec6efa"
```

**What happens internally:**

1. **Gateway validates JWT token** (same as upload)

2. **Gateway retrieves MP3 from MongoDB**:
   ```python
   # gateway/storage/util.py
   mp3_file = fs_mp3s.get(ObjectId(fid))
   ```

3. **Gateway streams file to client**:
   ```python
   return send_file(mp3_file, download_name=f"{fid}.mp3")
   ```

**Verify download:**
```bash
# Check file was downloaded
ls -lh mp3_download.mp3
# Should show file size (e.g., 5.2M)

# Play the MP3 (if you have mpv or vlc installed)
mpv mp3_download.mp3
# or
vlc mp3_download.mp3

# Check file type
file mp3_download.mp3
# Expected: mp3_download.mp3: Audio file with ID3 version 2.4.0
```

---

## MySQL Database Operations

### Connection

**Connect from host:**
```bash
mysql -u auth_user -p -h 127.0.0.1 -P 3306
# Password: Auth123!
```

**Connect from pod:**
```bash
kubectl exec -it deployment/auth -- mysql -u auth_user -pAuth123! -h 192.168.49.1 auth
```

### Database Structure

**Show databases:**
```sql
SHOW DATABASES;
```

**Output:**
```
+--------------------+
| Database           |
+--------------------+
| auth               |
| information_schema |
+--------------------+
```

**Use auth database:**
```sql
USE auth;
```

**Show tables:**
```sql
SHOW TABLES;
```

**Output:**
```
+----------------+
| Tables_in_auth |
+----------------+
| user           |
+----------------+
```

**Describe user table:**
```sql
DESCRIBE user;
```

**Output:**
```
+----------+--------------+------+-----+---------+----------------+
| Field    | Type         | Null | Key | Default | Extra          |
+----------+--------------+------+-----+---------+----------------+
| id       | int          | NO   | PRI | NULL    | auto_increment |
| email    | varchar(255) | NO   | UNI | NULL    |                |
| password | varchar(255) | NO   |     | NULL    |                |
+----------+--------------+------+-----+---------+----------------+
```

### Query Users

**View all users:**
```sql
SELECT * FROM user;
```

**Output:**
```
+----+---------------------+-----------+
| id | email               | password  |
+----+---------------------+-----------+
|  1 | dksahuji@gmail.com  | Admin123  |
+----+---------------------+-----------+
```

**View specific user:**
```sql
SELECT * FROM user WHERE email = 'dksahuji@gmail.com';
```

**Count users:**
```sql
SELECT COUNT(*) FROM user;
```

**Find users with specific domain:**
```sql
SELECT * FROM user WHERE email LIKE '%@gmail.com';
```

### Manage Users

**Insert new user:**
```sql
INSERT INTO user (email, password)
VALUES ('newuser@example.com', 'SecurePass123');
```

**Update password:**
```sql
UPDATE user
SET password = 'NewPassword456'
WHERE email = 'dksahuji@gmail.com';
```

**Delete user:**
```sql
DELETE FROM user
WHERE email = 'newuser@example.com';
```

**Verify changes:**
```sql
SELECT * FROM user WHERE email = 'dksahuji@gmail.com';
```

### Advanced Queries

**Find users created recently** (if you have a created_at column):
```sql
-- First add created_at column
ALTER TABLE user ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Then query
SELECT * FROM user
WHERE created_at > DATE_SUB(NOW(), INTERVAL 7 DAY);
```

**User statistics:**
```sql
SELECT
    COUNT(*) as total_users,
    COUNT(DISTINCT SUBSTRING_INDEX(email, '@', -1)) as unique_domains
FROM user;
```

### Database Administration

**Check MySQL connection from pods:**
```bash
kubectl exec deployment/auth -- mysql -u auth_user -pAuth123! -h 192.168.49.1 -e "SELECT 1"
```

**View MySQL grants:**
```sql
-- As root user
sudo mysql -u root

SHOW GRANTS FOR 'auth_user'@'192.168.49.%';
```

**Output:**
```sql
GRANT ALL PRIVILEGES ON `auth`.* TO `auth_user`@`192.168.49.%`
```

**Check MySQL is listening on 0.0.0.0:**
```bash
ss -tlnp | grep 3306
```

**Expected:**
```
LISTEN  0  151  0.0.0.0:3306  0.0.0.0:*
```

---

## MongoDB Database Operations

### Connection

**Connect from host:**
```bash
mongosh mongodb://localhost:27017
```

**Connect from pod:**
```bash
kubectl exec -it deployment/gateway -- python3 -c "from pymongo import MongoClient; client = MongoClient('mongodb://192.168.49.1:27017'); print(client.server_info())"
```

**Interactive MongoDB shell from pod:**
```bash
kubectl exec -it deployment/gateway -- python3
>>> from pymongo import MongoClient
>>> client = MongoClient('mongodb://192.168.49.1:27017')
>>> db = client['videos']
>>> db.fs.files.find_one()
```

### Database Structure

**Show all databases:**
```javascript
show dbs
```

**Output:**
```
admin    40.00 KiB
config   12.00 KiB
local    72.00 KiB
mp3s     15.23 MiB
videos   52.41 MiB
```

**Use videos database:**
```javascript
use videos
```

**Show collections:**
```javascript
show collections
```

**Output:**
```
fs.chunks
fs.files
```

**GridFS structure explanation:**
- `fs.files`: Stores file metadata (filename, length, uploadDate, etc.)
- `fs.chunks`: Stores actual file data in 255KB chunks

### Query Video Files

**View all video files (metadata):**
```javascript
db.fs.files.find().pretty()
```

**Sample output:**
```javascript
{
  _id: ObjectId("6908d08362046551e1ec6efb"),
  length: 52428800,
  chunkSize: 261120,
  uploadDate: ISODate("2025-11-03T14:30:45.123Z"),
  filename: "agentic_ai-using-external-feedback.mp4",
  contentType: "video/mp4",
  metadata: {
    username: "dksahuji@gmail.com"
  }
}
```

**Count video files:**
```javascript
db.fs.files.count()
```

**Find videos by user:**
```javascript
db.fs.files.find({ "metadata.username": "dksahuji@gmail.com" }).pretty()
```

**Find videos uploaded today:**
```javascript
const today = new Date()
today.setHours(0, 0, 0, 0)

db.fs.files.find({
  uploadDate: { $gte: today }
}).pretty()
```

**Find large videos (> 100MB):**
```javascript
db.fs.files.find({
  length: { $gt: 100 * 1024 * 1024 }
}).pretty()
```

**Get file by ObjectId:**
```javascript
db.fs.files.findOne({ _id: ObjectId("6908d08362046551e1ec6efb") })
```

### Query MP3 Files

**Switch to mp3s database:**
```javascript
use mp3s
```

**View all MP3 files:**
```javascript
db.fs.files.find().pretty()
```

**Sample output:**
```javascript
{
  _id: ObjectId("6908d08362046551e1ec6efc"),
  length: 5242880,
  chunkSize: 261120,
  uploadDate: ISODate("2025-11-03T14:35:12.456Z"),
  filename: "6908d08362046551e1ec6efb.mp3",
  contentType: "audio/mpeg",
  metadata: {
    video_fid: "6908d08362046551e1ec6efb",
    username: "dksahuji@gmail.com"
  }
}
```

**Find MP3s by video_fid:**
```javascript
db.fs.files.find({
  "metadata.video_fid": "6908d08362046551e1ec6efb"
}).pretty()
```

### Storage Statistics

**Calculate total storage used:**
```javascript
use videos
db.fs.files.aggregate([
  {
    $group: {
      _id: null,
      totalBytes: { $sum: "$length" },
      totalFiles: { $sum: 1 },
      avgFileSize: { $avg: "$length" }
    }
  },
  {
    $project: {
      _id: 0,
      totalMB: { $round: [{ $divide: ["$totalBytes", 1048576] }, 2] },
      totalFiles: 1,
      avgSizeMB: { $round: [{ $divide: ["$avgFileSize", 1048576] }, 2] }
    }
  }
])
```

**Output:**
```javascript
{
  totalMB: 52.41,
  totalFiles: 12,
  avgSizeMB: 4.37
}
```

**Storage by user:**
```javascript
db.fs.files.aggregate([
  {
    $group: {
      _id: "$metadata.username",
      totalFiles: { $sum: 1 },
      totalBytes: { $sum: "$length" }
    }
  },
  {
    $project: {
      username: "$_id",
      totalFiles: 1,
      totalMB: { $round: [{ $divide: ["$totalBytes", 1048576] }, 2] }
    }
  },
  {
    $sort: { totalMB: -1 }
  }
])
```

**Files uploaded per day:**
```javascript
db.fs.files.aggregate([
  {
    $group: {
      _id: {
        $dateToString: { format: "%Y-%m-%d", date: "$uploadDate" }
      },
      count: { $sum: 1 }
    }
  },
  {
    $sort: { _id: -1 }
  }
])
```

### GridFS Chunks

**View chunk information for a file:**
```javascript
// Get file info
const file = db.fs.files.findOne({ _id: ObjectId("6908d08362046551e1ec6efb") })

// Count chunks for this file
db.fs.chunks.count({ files_id: file._id })

// View first chunk
db.fs.chunks.findOne({ files_id: file._id, n: 0 })
```

**Sample chunk output:**
```javascript
{
  _id: ObjectId("6908d08362046551e1ec6efd"),
  files_id: ObjectId("6908d08362046551e1ec6efb"),
  n: 0,
  data: Binary(Buffer.from("..."), 0)
}
```

### Delete Files

**Delete a specific file:**
```javascript
// This will NOT delete chunks automatically
db.fs.files.deleteOne({ _id: ObjectId("6908d08362046551e1ec6efc") })

// Must also delete chunks
db.fs.chunks.deleteMany({ files_id: ObjectId("6908d08362046551e1ec6efc") })
```

**Better: Use GridFSBucket delete** (from Python):
```python
kubectl exec -it deployment/gateway -- python3
>>> from pymongo import MongoClient
>>> from gridfs import GridFSBucket
>>> client = MongoClient('mongodb://192.168.49.1:27017')
>>> db = client['mp3s']
>>> fs = GridFSBucket(db)
>>> from bson import ObjectId
>>> fs.delete(ObjectId("6908d08362046551e1ec6efc"))
>>> # This automatically deletes both file and chunks
```

**Delete old files (older than 30 days):**
```javascript
const thirtyDaysAgo = new Date()
thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)

// Get old file IDs
const oldFiles = db.fs.files.find({
  uploadDate: { $lt: thirtyDaysAgo }
}).map(f => f._id)

// Delete files
db.fs.files.deleteMany({
  uploadDate: { $lt: thirtyDaysAgo }
})

// Delete chunks
db.fs.chunks.deleteMany({
  files_id: { $in: oldFiles }
})
```

### Database Administration

**Check MongoDB is listening:**
```bash
ss -tlnp | grep 27017
```

**Expected:**
```
LISTEN  0  4096  0.0.0.0:27017  0.0.0.0:*
```

**Test connection from pod:**
```bash
kubectl exec deployment/gateway -- python3 -c "from pymongo import MongoClient; print('Connected!' if MongoClient('mongodb://192.168.49.1:27017').server_info() else 'Failed')"
```

**Database statistics:**
```javascript
use videos
db.stats()
```

**Output:**
```javascript
{
  db: 'videos',
  collections: 2,
  views: 0,
  objects: 150,
  avgObjSize: 261120,
  dataSize: 52428800,
  storageSize: 53477376,
  indexes: 2,
  indexSize: 49152,
  totalSize: 53526528,
  scaleFactor: 1,
  fsUsedSize: 15032385536,
  fsTotalSize: 62725623808,
  ok: 1
}
```

---

## RabbitMQ Queue Management

### Access Management UI

**Port forward:**
```bash
kubectl port-forward pod/rabbitmq-0 15672:15672
```

**Open browser:**
```
http://localhost:15672
```

**Login:**
- Username: `guest`
- Password: `guest`

### View Queues via CLI

**List queues:**
```bash
kubectl exec -it rabbitmq-0 -- rabbitmqctl list_queues
```

**Output:**
```
Listing queues for vhost / ...
name    messages
mp3     0
video   0
```

**Detailed queue info:**
```bash
kubectl exec -it rabbitmq-0 -- rabbitmqctl list_queues name messages consumers message_bytes
```

### Monitor Queue Activity

**Watch queue in real-time:**
```bash
watch -n 1 'kubectl exec rabbitmq-0 -- rabbitmqctl list_queues name messages consumers'
```

**Check queue depth over time:**
```bash
while true; do
  echo "$(date): $(kubectl exec rabbitmq-0 -- rabbitmqctl list_queues | grep video | awk '{print $2}') messages in video queue"
  sleep 5
done
```

### Publish Test Message

**Publish to video queue:**
```bash
kubectl exec -it rabbitmq-0 -- python3 << 'EOF'
import pika
import json

connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()

message = {
    "video_fid": "507f1f77bcf86cd799439011",
    "mp3_fid": None,
    "username": "dksahuji@gmail.com"
}

channel.basic_publish(
    exchange='',
    routing_key='video',
    body=json.dumps(message)
)

print(f"Published test message: {message}")
connection.close()
EOF
```

### Consume Messages Manually

**Peek at messages (without consuming):**
```bash
kubectl exec -it rabbitmq-0 -- rabbitmqadmin get queue=video count=5
```

**Consume messages from video queue:**
```bash
kubectl exec -it rabbitmq-0 -- python3 << 'EOF'
import pika

connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()

def callback(ch, method, properties, body):
    print(f"Received: {body.decode()}")
    ch.basic_ack(delivery_tag=method.delivery_tag)

channel.basic_consume(queue='video', on_message_callback=callback)
print('Waiting for messages. Press Ctrl+C to exit.')

try:
    channel.start_consuming()
except KeyboardInterrupt:
    channel.stop_consuming()

connection.close()
EOF
```

### Queue Management

**Purge queue (delete all messages):**
```bash
kubectl exec rabbitmq-0 -- rabbitmqctl purge_queue video
kubectl exec rabbitmq-0 -- rabbitmqctl purge_queue mp3
```

**Delete queue:**
```bash
kubectl exec rabbitmq-0 -- rabbitmqctl delete_queue video
```

**Create queue:**
```bash
kubectl exec rabbitmq-0 -- rabbitmqadmin declare queue name=video durable=true
```

---

## Monitoring & Debugging

### Check Pod Status

**All pods:**
```bash
kubectl get pods
```

**Specific service:**
```bash
kubectl get pods -l app=converter
kubectl get pods -l app=notification
kubectl get pods -l app=gateway
kubectl get pods -l app=auth
```

**Wide output (shows node, IP):**
```bash
kubectl get pods -o wide
```

### View Logs

**Gateway logs:**
```bash
kubectl logs -l app=gateway -f --tail=50
```

**Auth logs:**
```bash
kubectl logs -l app=auth -f --tail=50
```

**Converter logs (all workers):**
```bash
kubectl logs -l app=converter -f --tail=50
```

**Converter logs (specific pod):**
```bash
kubectl logs converter-xxxxxxxxx-xxxxx -f
```

**Notification logs:**
```bash
kubectl logs -l app=notification -f --tail=50
```

**RabbitMQ logs:**
```bash
kubectl logs rabbitmq-0 -f --tail=50
```

**Previous logs (if pod crashed):**
```bash
kubectl logs <pod-name> --previous
```

### Describe Resources

**Describe pod:**
```bash
kubectl describe pod <pod-name>
```

**Key sections to check:**
- **Status**: Running / CrashLoopBackOff / Error
- **Events**: Recent events (pulled image, started container, etc.)
- **Containers**: Container status and restart count

**Describe service:**
```bash
kubectl describe service gateway
```

**Check endpoints:**
```bash
kubectl get endpoints gateway
```

**Expected output:**
```
NAME      ENDPOINTS                          AGE
gateway   10.244.0.5:8080,10.244.0.6:8080   5m
```

### Shell into Pods

**Gateway:**
```bash
kubectl exec -it deployment/gateway -- /bin/bash
```

**Inside pod:**
```bash
# Test MongoDB connection
python3 -c "from pymongo import MongoClient; print(MongoClient('mongodb://192.168.49.1:27017').server_info())"

# Test Auth service
curl -v http://auth:5000/login

# Check environment variables
env | grep MONGODB
```

**Auth:**
```bash
kubectl exec -it deployment/auth -- /bin/bash

# Test MySQL connection
mysql -u auth_user -pAuth123! -h 192.168.49.1 auth -e "SELECT * FROM user;"

# Check environment
env | grep MYSQL
```

### Test Connectivity

**From host to pod:**
```bash
# Port forward first
kubectl port-forward service/gateway 8080:8080

# Then test
curl http://localhost:8080/login
```

**From pod to host database:**
```bash
# MySQL
kubectl exec deployment/auth -- nc -zv 192.168.49.1 3306

# MongoDB
kubectl exec deployment/gateway -- nc -zv 192.168.49.1 27017
```

**Between pods:**
```bash
# Gateway to Auth
kubectl exec deployment/gateway -- curl -v http://auth:5000/login

# Converter to RabbitMQ
kubectl exec deployment/converter -- nc -zv rabbitmq 5672
```

### Resource Usage

**Pod resource usage:**
```bash
kubectl top pods
```

**Output:**
```
NAME                           CPU(cores)   MEMORY(bytes)
auth-xxxxxxxxx-xxxxx           10m          125Mi
gateway-xxxxxxxxx-xxxxx        15m          256Mi
converter-xxxxxxxxx-xxxxx      250m         512Mi
notification-xxxxxxxxx-xxxxx   5m           100Mi
rabbitmq-0                     50m          256Mi
```

**Node resource usage:**
```bash
kubectl top nodes
```

### Check ConfigMaps and Secrets

**View ConfigMap:**
```bash
kubectl get configmap auth-configmap -o yaml
kubectl get configmap gateway-configmap -o yaml
```

**View Secret (base64 encoded):**
```bash
kubectl get secret auth-secret -o yaml
```

**Decode secret:**
```bash
kubectl get secret auth-secret -o jsonpath='{.data.JWT_SECRET}' | base64 -d
echo
```

### Events

**View all events:**
```bash
kubectl get events --sort-by='.lastTimestamp'
```

**View events for specific pod:**
```bash
kubectl get events --field-selector involvedObject.name=<pod-name>
```

---

## API Reference

### POST /login

**Description**: Authenticate user and get JWT token

**URL**: `http://video2mp3.com/login`

**Method**: `POST`

**Auth**: Basic Auth (email:password)

**Request:**
```bash
curl -X POST \
  -u 'dksahuji@gmail.com:Admin123' \
  http://video2mp3.com/login
```

**Response (Success - 200):**
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImRrc2FodWppQGdtYWlsLmNvbSIsImV4cCI6MTczMDc5MjAwMH0.xxx
```

**Response (Failure - 401):**
```
Unauthorized
```

---

### POST /upload

**Description**: Upload video file for conversion

**URL**: `http://video2mp3.com/upload`

**Method**: `POST`

**Auth**: Bearer Token (JWT from /login)

**Content-Type**: `multipart/form-data`

**Request:**
```bash
curl -X POST \
  -H "Authorization: Bearer <jwt_token>" \
  -F "file=@./video.mp4" \
  http://video2mp3.com/upload
```

**Response (Success - 200):**
```
success!
```

**Response (Unauthorized - 401):**
```
Unauthorized
```

**Response (Bad Request - 400):**
```
No file provided
```

---

### GET /download

**Description**: Download converted MP3 file

**URL**: `http://video2mp3.com/download?fid=<ObjectId>`

**Method**: `GET`

**Auth**: Bearer Token (JWT from /login)

**Query Parameters:**
- `fid` (required): MongoDB ObjectId of the MP3 file

**Request:**
```bash
curl -X GET \
  -H "Authorization: Bearer <jwt_token>" \
  "http://video2mp3.com/download?fid=6908d08362046551e1ec6efa" \
  -o output.mp3
```

**Response (Success - 200):**
- Binary MP3 file stream
- Content-Type: `audio/mpeg`

**Response (Unauthorized - 401):**
```
Unauthorized
```

**Response (Not Found - 404):**
```
File not found
```

---

## Troubleshooting Guide

### Issue: Login fails with 401

**Symptoms:**
```bash
$ curl -X POST -u 'dksahuji@gmail.com:Admin123' http://video2mp3.com/login
Unauthorized
```

**Diagnosis:**
```bash
# Check auth pod logs
kubectl logs -l app=auth --tail=20

# Check MySQL connection
kubectl exec deployment/auth -- mysql -u auth_user -pAuth123! -h 192.168.49.1 auth -e "SELECT * FROM user;"

# Verify credentials in MySQL
sudo mysql -u root -e "SELECT * FROM auth.user WHERE email='dksahuji@gmail.com';"
```

**Solutions:**
1. Verify user exists in MySQL: `SELECT * FROM auth.user;`
2. Check password matches: `Admin123`
3. Verify MySQL is accessible from pods: `kubectl exec deployment/auth -- nc -zv 192.168.49.1 3306`
4. Check bind-address in MySQL: `cat /etc/mysql/mysql.conf.d/mysqld.cnf | grep bind-address` (should be `0.0.0.0`)

---

### Issue: Upload fails with 500

**Symptoms:**
```bash
$ curl -X POST -F 'file=@video.mp4' -H "Authorization: Bearer $TOKEN" http://video2mp3.com/upload
Internal Server Error
```

**Diagnosis:**
```bash
# Check gateway logs
kubectl logs -l app=gateway --tail=50

# Look for MongoDB connection errors
kubectl logs -l app=gateway | grep -i mongo

# Test MongoDB connection
kubectl exec deployment/gateway -- python3 -c "from pymongo import MongoClient; print(MongoClient('mongodb://192.168.49.1:27017').server_info())"
```

**Solutions:**
1. Verify MongoDB is running: `ss -tlnp | grep 27017`
2. Check MongoDB bind IP: `cat /etc/mongod.conf | grep bindIp` (should be `0.0.0.0`)
3. Test connection from pod: `kubectl exec deployment/gateway -- nc -zv 192.168.49.1 27017`
4. Restart MongoDB: `sudo systemctl restart mongod`
5. Check gateway configmap has correct host: `kubectl get configmap gateway-configmap -o yaml | grep MONGODB_HOST`

---

### Issue: No email received

**Symptoms:**
- Upload succeeds
- Converter processes video
- No email notification

**Diagnosis:**
```bash
# Check notification pod logs
kubectl logs -l app=notification --tail=50

# Check RabbitMQ mp3 queue
kubectl exec rabbitmq-0 -- rabbitmqctl list_queues | grep mp3

# Check Gmail credentials
kubectl get secret notification-secret -o jsonpath='{.data.GMAIL_ADDRESS}' | base64 -d
echo
kubectl get secret notification-secret -o jsonpath='{.data.GMAIL_PASSWORD}' | base64 -d
echo
```

**Common causes:**

1. **Invalid Gmail credentials:**
   ```bash
   # Test login
   kubectl exec -it deployment/notification -- python3 -c "
   import smtplib
   session = smtplib.SMTP('smtp.gmail.com', 587)
   session.starttls()
   session.login('your-email@gmail.com', 'app-password')
   print('Success')
   "
   ```

2. **Using regular password instead of App Password:**
   - Go to https://myaccount.google.com/security
   - Enable 2FA
   - Generate App Password for Mail
   - Update .env file
   - Redeploy: `./deploy.sh`

3. **Messages stuck in queue:**
   ```bash
   # Purge and retry
   kubectl exec rabbitmq-0 -- rabbitmqctl purge_queue mp3
   # Re-upload video
   ```

---

### Issue: Conversion fails

**Symptoms:**
```bash
$ kubectl logs -l app=converter
Error converting video: ...
```

**Diagnosis:**
```bash
# Check converter logs
kubectl logs -l app=converter --tail=100

# Check FFmpeg is installed
kubectl exec deployment/converter -- ffmpeg -version

# Check MongoDB connection
kubectl exec deployment/converter -- python3 -c "from pymongo import MongoClient; print(MongoClient('mongodb://192.168.49.1:27017').server_info())"

# Check video queue
kubectl exec rabbitmq-0 -- rabbitmqctl list_queues | grep video
```

**Solutions:**
1. Check video format is supported
2. Verify FFmpeg is in Docker image
3. Check pod has enough memory: `kubectl top pods | grep converter`
4. Increase memory limit in converter-deploy.yaml
5. Check temp file cleanup: `kubectl exec deployment/converter -- df -h`

---

### Issue: Port forwarding not working

**Symptoms:**
```bash
$ curl http://video2mp3.com/login
curl: (7) Failed to connect to video2mp3.com port 80: Connection refused
```

**Diagnosis:**
```bash
# Check port forwards are running
ps aux | grep "kubectl port-forward"

# Check logs
tail -f /tmp/gateway-pf.log
tail -f /tmp/auth-pf.log

# Check /etc/hosts
cat /etc/hosts | grep video2mp3.com
```

**Solutions:**
1. Stop all forwards: `sudo pkill -f 'kubectl port-forward'`
2. Restart: `./start-services.sh`
3. Check sudo access (needed for port 80)
4. Verify pods are running: `kubectl get pods`
5. Check gateway service: `kubectl get service gateway`

---

### Issue: Pod stuck in CrashLoopBackOff

**Symptoms:**
```bash
$ kubectl get pods
NAME                           READY   STATUS             RESTARTS   AGE
converter-xxxxxxxxx-xxxxx      0/1     CrashLoopBackOff   5          5m
```

**Diagnosis:**
```bash
# Check pod logs
kubectl logs <pod-name>

# Check previous logs
kubectl logs <pod-name> --previous

# Describe pod for events
kubectl describe pod <pod-name>
```

**Solutions:**
1. Check logs for error message
2. Verify environment variables in configmap
3. Check Docker image was pushed: `docker pull dksahuji/video2mp3-converter:latest`
4. Verify dependencies are installed
5. Check resource limits: `kubectl describe pod <pod-name> | grep -A 5 Limits`

---

## Quick Reference Commands

### Deployment
```bash
# First time only
./setup-host.sh

# Deploy all services
./deploy.sh

# Start port forwarding
./start-services.sh

# Undeploy everything
./undeploy.sh

# Stop port forwarding
sudo pkill -f 'kubectl port-forward'
```

### Testing
```bash
# Login
TOKEN=$(curl -X POST -u 'dksahuji@gmail.com:Admin123' http://video2mp3.com/login 2>/dev/null)

# Upload
curl -X POST -F 'file=@video.mp4' -H "Authorization: Bearer $TOKEN" http://video2mp3.com/upload

# Download (replace <fid>)
curl --output output.mp3 -X GET -H "Authorization: Bearer $TOKEN" "http://video2mp3.com/download?fid=<fid>"
```

### Monitoring
```bash
# All pods
kubectl get pods

# Logs
kubectl logs -l app=gateway -f
kubectl logs -l app=converter -f
kubectl logs -l app=notification -f

# Resources
kubectl top pods

# Events
kubectl get events --sort-by='.lastTimestamp'
```

### Databases
```bash
# MySQL
mysql -u auth_user -pAuth123! -h 127.0.0.1 auth

# MongoDB
mongosh mongodb://localhost:27017

# RabbitMQ
kubectl exec rabbitmq-0 -- rabbitmqctl list_queues
```

---

## Production Considerations

### Scaling

**Scale converter workers:**
```bash
kubectl scale deployment converter --replicas=8
```

**Scale notification workers:**
```bash
kubectl scale deployment notification --replicas=8
```

**Auto-scaling (HPA):**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: converter-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: converter
  minReplicas: 4
  maxReplicas: 16
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Security

1. **Use TLS**: Enable HTTPS with cert-manager
2. **Secret management**: Use external secret store (Vault, AWS Secrets Manager)
3. **Network policies**: Restrict pod-to-pod communication
4. **RBAC**: Limit service account permissions
5. **Password hashing**: Use bcrypt in MySQL (currently plaintext!)

### High Availability

1. **Database replication**: MySQL primary-replica, MongoDB replica set
2. **RabbitMQ cluster**: Multi-node RabbitMQ
3. **Persistent volumes**: Use networked storage (NFS, Ceph)
4. **Load balancing**: Use cloud load balancer instead of port forwarding
5. **Multi-zone deployment**: Spread pods across availability zones

---

**Generated from:** `run-demo.sh`

**Last Updated:** 2025-01-03 (Updated to match run-demo.sh script)

**See also:**
- [README.md](./README.md) - Project overview
- [QUICKSTART.md](./QUICKSTART.md) - Quick setup guide
- [README-COMPLETE.md](./README-COMPLETE.md) - Complete architecture guide
- [DEPLOYMENT.md](./DEPLOYMENT.md) - Deployment options
- [DEBUGGING-GUIDE.md](./DEBUGGING-GUIDE.md) - Debugging methodologies
