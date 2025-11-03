# Notification Service

Email notification service for the video2mp3 microservices system.

## Overview

The Notification service provides:
- Email notifications when MP3 conversion is complete
- RabbitMQ consumer that listens for conversion completion messages
- Gmail SMTP integration for sending emails
- Scalable worker architecture (4 replicas by default)

## Architecture

```
RabbitMQ "mp3" queue
    “
Notification Workers (4 replicas)
    “
Gmail SMTP (smtp.gmail.com:587)
    “
User receives email notification
```

## How It Works

### Notification Flow

1. **Consume Message** - Worker listens on RabbitMQ `mp3` queue
2. **Parse Message** - Extract mp3_fid and username from message
3. **Compose Email** - Create email with MP3 file ID
4. **Send via SMTP** - Send email through Gmail SMTP server
5. **Acknowledge** - ACK message to RabbitMQ (or NACK on failure)

### Message Format

**Input (from "mp3" queue):**
```json
{
  "video_fid": "<MongoDB ObjectId>",
  "mp3_fid": "<MongoDB ObjectId>",
  "username": "dksahuji@gmail.com"
}
```

### Email Content

**Subject:** MP3 Download

**Body:**
```
mp3 file_id: <mp3_fid> is now ready!
```

**From:** Gmail account (configured via GMAIL_ADDRESS)

**To:** User's email (from message.username)

## Components

### consumer.py
Main consumer loop that:
- Connects to RabbitMQ
- Consumes messages from `mp3` queue
- Calls `email.notification()` for each message
- Handles acknowledgments (ACK/NACK)
- Implements error handling

### send/email.py
Email sending logic that:
- Parses JSON message from queue
- Creates EmailMessage with mp3_fid information
- Connects to Gmail SMTP server (smtp.gmail.com:587)
- Authenticates with Gmail credentials
- Sends email to user
- Uses TLS for secure connection

## Configuration

### Environment Variables (ConfigMap)
- `MP3_QUEUE` - RabbitMQ queue name for MP3 completion messages (default: "mp3")
- `VIDEO_QUEUE` - Not used by notification service (inherited from configmap)

### Secrets
- `GMAIL_ADDRESS` - Gmail account email address for sending notifications
- `GMAIL_PASSWORD` - Gmail app password (NOT your regular Gmail password)

**Important:** You must use a Gmail App Password, not your regular password. See [Gmail App Passwords](https://support.google.com/accounts/answer/185833) for setup instructions.

## Gmail Setup

### Prerequisites

1. **Gmail Account** - You need a Gmail account for sending emails
2. **2-Factor Authentication** - Must be enabled on your Gmail account
3. **App Password** - Generate an app-specific password

### Generate Gmail App Password

1. Go to Google Account settings: https://myaccount.google.com/
2. Navigate to Security ’ 2-Step Verification
3. Scroll down to "App passwords"
4. Generate a new app password for "Mail"
5. Copy the 16-character password
6. Use this password in the secret.yaml.template

### Configure Secret

Edit `.env` file in project root:
```bash
GMAIL_ADDRESS="your-email@gmail.com"
GMAIL_PASSWORD="your-16-char-app-password"
```

## Docker Build & Deploy

### Build Docker Image
```bash
cd src/notification
docker build -t dksahuji/notification:latest .
```

### Push to Docker Hub
```bash
docker push dksahuji/notification:latest
```

## Kubernetes Deployment

### Deploy Notification Service
```bash
cd src/notification/manifests
envsubst < secret.yaml.template | kubectl apply -f -
kubectl apply -f configmap.yaml
kubectl apply -f notification-deploy.yaml
```

This creates:
- `deployment.apps/notification` - 4 replicas for parallel email sending
- `configmap/notification-configmap` - Queue configuration
- `secret/notification-secret` - Gmail credentials

### Undeploy
```bash
kubectl delete deployment notification
kubectl delete configmap notification-configmap
kubectl delete secret notification-secret
```

### Scale Workers
```bash
# Scale to 8 workers for higher throughput
kubectl scale deployment notification --replicas=8

# Check workers
kubectl get pods -l app=notification
```

**Scaling Strategy:**
- More workers = more parallel email sending
- Each worker processes one notification at a time
- RollingUpdate strategy with maxSurge: 8

## Monitoring & Debugging

### Check Deployment Status
```bash
# View pods
kubectl get pods -l app=notification

# View logs from all workers
kubectl logs -l app=notification --tail=50 -f

# View logs from specific pod
kubectl logs <pod-name> -f
```

### Shell into Worker Pod
```bash
kubectl exec -it deployment/notification -- /bin/bash

# Test RabbitMQ connection
python3 -c "import pika; conn = pika.BlockingConnection(pika.ConnectionParameters('rabbitmq')); print('Connected')"
```

### Monitor RabbitMQ Queue
```bash
# Port forward to RabbitMQ Management UI
kubectl port-forward pod/rabbitmq-0 15672:15672

# Open browser: http://localhost:15672
# Login: guest / guest
# Check "mp3" queue for pending messages
```

## Common Issues

### Emails Not Being Sent

**Problem:** Worker crashes or emails fail to send

**Check logs:**
```bash
kubectl logs -l app=notification
```

**Common causes:**
1. **Invalid Gmail credentials:**
   - Verify GMAIL_ADDRESS and GMAIL_PASSWORD in secret
   - Ensure using App Password, not regular password
   - Check 2FA is enabled on Gmail account

2. **Gmail SMTP blocked:**
   - Gmail may block sign-ins from less secure apps
   - Use App Password instead of regular password
   - Check for security alerts in your Gmail account

3. **Network issues:**
   - Verify pods can reach smtp.gmail.com:587
   - Check firewall rules

**Test Gmail credentials:**
```bash
kubectl exec -it deployment/notification -- python3 -c "
import smtplib
session = smtplib.SMTP('smtp.gmail.com', 587)
session.starttls()
session.login('your-email@gmail.com', 'your-app-password')
print('Login successful')
session.quit()
"
```

### Messages Not Being Consumed

**Problem:** RabbitMQ connection issues

**Check RabbitMQ:**
```bash
kubectl get pods -l app=rabbitmq
kubectl logs rabbitmq-0

# Check RabbitMQ service
kubectl get service rabbitmq
```

**Test from pod:**
```bash
kubectl exec deployment/notification -- python3 -c "
import pika
connection = pika.BlockingConnection(pika.ConnectionParameters('rabbitmq'))
channel = connection.channel()
print('Connected to RabbitMQ')
"
```

### Queue Growing Too Large

**Problem:** Notification workers can't keep up with conversion rate

**Solutions:**
1. Scale notification workers: `kubectl scale deployment notification --replicas=8`
2. Check for notification errors: `kubectl logs -l app=notification`
3. Monitor via Management UI: http://localhost:15672

### Gmail Rate Limiting

**Problem:** Gmail blocks too many emails sent quickly

**Gmail Limits:**
- ~100 emails per day for free Gmail accounts
- ~2000 emails per day for Google Workspace accounts

**Solutions:**
1. Use Google Workspace account for higher limits
2. Implement exponential backoff in email.py
3. Use a different email service provider (SendGrid, AWS SES, etc.)

## Performance

### Throughput
- Single worker can send ~5-10 emails/second
- Gmail rate limits may restrict throughput
- Scale workers for higher concurrency (not higher rate)

### Resource Usage
- Memory: ~100Mi per pod
- CPU: Minimal (mostly waiting on SMTP)
- Network: Low bandwidth usage

## Testing

### End-to-End Test
```bash
# 1. Upload video
TOKEN=$(curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login 2>/dev/null)
curl -X POST -F "file=@test.mp4" \
  -H "Authorization: Bearer $TOKEN" \
  http://video2mp3.com/upload

# 2. Watch notification logs
kubectl logs -l app=notification -f

# 3. Check your email inbox
# You should receive: "mp3 file_id: <ObjectId> is now ready!"
```

### Manual Test Message
```bash
# Publish test message to mp3 queue
kubectl exec -it deployment/notification -- python3

>>> import pika, json
>>> connection = pika.BlockingConnection(pika.ConnectionParameters('rabbitmq'))
>>> channel = connection.channel()
>>> message = {
...     "video_fid": "507f1f77bcf86cd799439011",
...     "mp3_fid": "507f191e810c19729de860ea",
...     "username": "dksahuji@gmail.com"
... }
>>> channel.basic_publish(
...     exchange='',
...     routing_key='mp3',
...     body=json.dumps(message)
... )
>>> print("Test message published")
```

## Error Handling

### Email Send Failures
- If email sending fails: NACK message (returns to queue)
- Message will be retried by another worker
- Check logs for specific error details

### RabbitMQ Connection Issues
- Consumers automatically reconnect on connection loss
- Messages are not lost due to persistent queue
- Workers will resume consuming after reconnection

## Files

- `consumer.py` - RabbitMQ consumer loop and message handling
- `send/email.py` - Email sending logic via Gmail SMTP
- `send/__init__.py` - Package initialization
- `Dockerfile` - Python 3.12-slim container
- `pyproject.toml` - Dependencies: pika (RabbitMQ client)
- `manifests/` - Kubernetes deployment files
  - `notification-deploy.yaml` - Deployment with 4 replicas
  - `configmap.yaml` - Queue configuration
  - `secret.yaml.template` - Gmail credentials template

## Development Workflow

```bash
# 1. Make code changes
vim consumer.py
vim send/email.py

# 2. Rebuild Docker image
docker build -t dksahuji/notification:latest .
docker push dksahuji/notification:latest

# 3. Restart deployment
kubectl rollout restart deployment/notification
kubectl rollout status deployment/notification

# 4. Monitor logs
kubectl logs -l app=notification --tail=50 -f

# 5. Test notification
# Upload a video and check email
```

## Security Best Practices

1. **Never commit Gmail credentials** - Use secret.yaml.template
2. **Use App Passwords** - Not your main Gmail password
3. **Rotate credentials regularly** - Generate new app passwords periodically
4. **Use environment variables** - Keep secrets out of code
5. **Enable 2FA** - Required for app passwords

## Alternative Email Providers

If Gmail doesn't meet your needs, consider:

### SendGrid
- Higher rate limits
- Better deliverability
- API-based (easier than SMTP)
- Free tier: 100 emails/day

### AWS SES
- Very high limits
- Pay-as-you-go pricing
- Requires AWS account
- Good for production

### Mailgun
- Developer-friendly API
- Free tier: 100 emails/day
- Good documentation

## Resources

- [Gmail SMTP Settings](https://support.google.com/mail/answer/7126229)
- [Gmail App Passwords](https://support.google.com/accounts/answer/185833)
- [Python smtplib Documentation](https://docs.python.org/3/library/smtplib.html)
- [Python email.message Documentation](https://docs.python.org/3/library/email.message.html)
- [Pika Documentation](https://pika.readthedocs.io/)

## Related Documentation

- **RabbitMQ setup:** [../rabbitMQ/README.md](../rabbitMQ/README.md)
- **Converter service:** [../converter/README.md](../converter/README.md)
- **General debugging:** [../../DEBUGGING-GUIDE.md](../../DEBUGGING-GUIDE.md)
- **Project overview:** [../../README-COMPLETE.md](../../README-COMPLETE.md)
