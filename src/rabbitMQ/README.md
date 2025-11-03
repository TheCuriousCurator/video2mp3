# RabbitMQ Service

Message queue service for asynchronous video processing in the video2mp3 microservices system.

## Overview

RabbitMQ provides:
- Asynchronous task queue management
- Decoupling between Gateway (producer) and Converter (consumer)
- Message persistence and reliability
- Management UI for monitoring
- AMQP (Advanced Message Queuing Protocol) support

## Architecture

```
Gateway Service (Producer)
    ↓
RabbitMQ Broker
    ├→ "video" queue (conversion jobs)
    └→ "mp3" queue (completion notifications)
    ↓
Converter Workers (Consumers)
```

## Protocol: AMQP

**AMQP** = Advanced Message Queuing Protocol
- Industry-standard messaging protocol
- Reliable message delivery
- Supports routing, queuing, and pub/sub patterns
- Binary protocol for efficiency

## Queues

### "video" Queue
- **Purpose:** Incoming video conversion jobs
- **Producer:** Gateway service (on video upload)
- **Consumer:** Converter workers (4 replicas)
- **Message Format:**
  ```json
  {
    "video_fid": "<MongoDB ObjectId>",
    "mp3_fid": null,
    "username": "dksahuji@gmail.com"
  }
  ```

### "mp3" Queue
- **Purpose:** Conversion completion notifications
- **Producer:** Converter workers (after conversion)
- **Consumer:** None (used for auditing/logging)
- **Message Format:**
  ```json
  {
    "video_fid": "<MongoDB ObjectId>",
    "mp3_fid": "<MongoDB ObjectId>",
    "username": "dksahuji@gmail.com"
  }
  ```

## Deployment Type: StatefulSet

RabbitMQ is deployed as a **StatefulSet** (not Deployment) because:
- Requires stable network identity
- Needs persistent storage for queue data
- Maintains state across pod restarts
- Pod name is predictable: `rabbitmq-0`

## Management UI

### Access Management UI

**Default Credentials:**
- Username: `guest`
- Password: `guest`

**Via Port Forwarding (Recommended):**
```bash
kubectl port-forward pod/rabbitmq-0 15672:15672

# Open browser: http://localhost:15672
# Or: http://rabbitmq-manager.com:15672
```

**Via Ingress:**
```bash
# Add to /etc/hosts
sudo vim /etc/hosts
# Add: 192.168.49.2 rabbitmq-manager.com

# Access: http://rabbitmq-manager.com
```

See [solution tunnel.md](./solution%20tunnel.md) for detailed networking options.

## Configuration

### Environment Variables (ConfigMap)
- `RABBITMQ_DEFAULT_USER` - Admin username (default: guest)
- `RABBITMQ_DEFAULT_PASS` - Admin password (default: guest)

### Secrets
- RabbitMQ credentials (optional for production)

### Persistent Storage
RabbitMQ uses a PersistentVolumeClaim (PVC) to store:
- Queue data
- Message persistence
- Configuration

**Volume:**
- Name: `rabbitmq-pvc`
- Size: Configured in `pvc.yaml`
- Mount: `/var/lib/rabbitmq`

## Kubernetes Resources

### StatefulSet
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rabbitmq
spec:
  serviceName: "rabbitmq"
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq
```

### Service
- **Type:** ClusterIP (Headless)
- **Port 5672:** AMQP protocol (for producers/consumers)
- **Port 15672:** Management UI (HTTP)

### PersistentVolumeClaim
- Ensures queue data survives pod restarts
- Automatically provisions storage via Minikube

### Ingress (Optional)
- Routes external traffic to RabbitMQ Management UI
- Host: `rabbitmq-manager.com`

## Deployment

### Deploy RabbitMQ
```bash
cd src/rabbitMQ/manifests
kubectl apply -f ./
```

This creates:
- `statefulset.apps/rabbitmq` - 1 replica
- `service/rabbitmq` - Headless service for stable networking
- `configmap/rabbitmq-configmap` - Environment configuration
- `secret/rabbitmq-secret` - Credentials
- `pvc/rabbitmq-pvc` - Persistent storage
- `ingress/rabbitmq-ingress` - Optional external access

### Undeploy
```bash
kubectl delete -f ./
```

**Note:** PersistentVolume may remain. To fully clean up:
```bash
kubectl delete pvc rabbitmq-pvc
kubectl delete pv --all  # Caution: Deletes all PVs
```

## Monitoring & Debugging

### Check RabbitMQ Status
```bash
# View StatefulSet
kubectl get statefulset rabbitmq

# View pod
kubectl get pods -l app=rabbitmq

# View service
kubectl get service rabbitmq

# View PVC
kubectl get pvc rabbitmq-pvc
```

### View Logs
```bash
kubectl logs rabbitmq-0 -f
```

### Shell into RabbitMQ Pod
```bash
kubectl exec -it rabbitmq-0 -- /bin/bash

# Inside pod - check queues
rabbitmqctl list_queues

# Check connections
rabbitmqctl list_connections

# Check users
rabbitmqctl list_users
```

### Check Queue Status via Management UI
1. Port forward: `kubectl port-forward pod/rabbitmq-0 15672:15672`
2. Open: http://localhost:15672
3. Login: guest / guest
4. Navigate to "Queues" tab
5. View "video" and "mp3" queue statistics

## Common Issues

### Can't Access Management UI
**Problem:** Port forwarding not working

**Solution:**
```bash
# Stop existing port forwards
pkill -f "kubectl port-forward.*rabbitmq"

# Start fresh
kubectl port-forward pod/rabbitmq-0 15672:15672

# Test
curl http://localhost:15672
```

### Pod Not Starting
**Problem:** PVC issues or resource constraints

**Check:**
```bash
kubectl describe pod rabbitmq-0
kubectl describe pvc rabbitmq-pvc
kubectl get events --sort-by='.lastTimestamp'
```

### Messages Not Being Consumed
**Problem:** Converter workers not connected

**Check:**
```bash
# View connections in Management UI
# Or via command line:
kubectl exec rabbitmq-0 -- rabbitmqctl list_connections

# Check converter pods
kubectl get pods -l app=converter
kubectl logs -l app=converter
```

### Queue Growing Too Large
**Problem:** Converters can't keep up with video uploads

**Solutions:**
1. Scale converter workers: `kubectl scale deployment converter --replicas=8`
2. Check for converter errors: `kubectl logs -l app=converter`
3. Monitor via Management UI: http://localhost:15672

## Message Durability

### Queue Persistence
RabbitMQ queues are configured for durability:
- Messages survive RabbitMQ restarts
- Stored on PersistentVolume
- Requires explicit message acknowledgment

### Acknowledgment Strategy
- **Converter:** Consumes with `auto_ack=False`
- **Success:** Sends ACK after MP3 upload completes
- **Failure:** Sends NACK, message returns to queue

## Performance

### Throughput
- Single RabbitMQ instance handles 1000s of messages/sec
- Bottleneck is typically converter processing time
- Scale converters (not RabbitMQ) for higher throughput

### Resource Usage
- Memory: ~256Mi idle, more under load
- CPU: Minimal when queue is small
- Disk: Grows with queue size and message persistence

## Testing

### Test Message Publishing
```bash
# From gateway pod
kubectl exec -it deployment/gateway -- python3

>>> import pika
>>> connection = pika.BlockingConnection(pika.ConnectionParameters('rabbitmq'))
>>> channel = connection.channel()
>>> channel.queue_declare(queue='video', durable=True)
>>> channel.basic_publish(exchange='', routing_key='video', body='test')
>>> print("Message published")
```

### Test Message Consuming
```bash
# From converter pod
kubectl exec -it deployment/converter -- python3

>>> import pika
>>> connection = pika.BlockingConnection(pika.ConnectionParameters('rabbitmq'))
>>> channel = connection.channel()
>>> method, properties, body = channel.basic_get(queue='video', auto_ack=True)
>>> print(body)
```

## Files

- `manifests/` - Kubernetes deployment files
  - `statefulset.yaml` - StatefulSet with 1 replica
  - `service.yaml` - Headless service for stable networking
  - `configmap.yaml` - Environment variables (RABBITMQ_DEFAULT_USER/PASS)
  - `secret.yaml` - Sensitive credentials
  - `pvc.yaml` - PersistentVolumeClaim for data storage
  - `ingress.yaml` - Optional external access to Management UI
- `solution tunnel.md` - Networking and port forwarding guide

## Setup for External Access

### Option 1: Port Forwarding (Recommended)
```bash
# Start port forward
kubectl port-forward pod/rabbitmq-0 15672:15672

# Add to /etc/hosts (optional)
echo "127.0.0.1 rabbitmq-manager.com" | sudo tee -a /etc/hosts

# Access: http://localhost:15672 or http://rabbitmq-manager.com:15672
```

### Option 2: Ingress
```bash
# Update /etc/hosts to point to minikube IP
MINIKUBE_IP=$(minikube ip)
echo "$MINIKUBE_IP rabbitmq-manager.com" | sudo tee -a /etc/hosts

# Enable ingress addon
minikube addons enable ingress

# Deploy ingress
kubectl apply -f manifests/ingress.yaml

# Access: http://rabbitmq-manager.com
```

See [solution tunnel.md](./solution%20tunnel.md) for detailed comparison.

## Resources

- [RabbitMQ Documentation](https://www.rabbitmq.com/documentation.html)
- [RabbitMQ Tutorials](https://www.rabbitmq.com/getstarted.html)
- [AMQP Protocol](https://www.rabbitmq.com/tutorials/amqp-concepts.html)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Pika (Python RabbitMQ Client)](https://pika.readthedocs.io/)

## Related Documentation

- **Networking guide:** [solution tunnel.md](./solution%20tunnel.md)
- **Converter service:** [../converter/README.md](../converter/README.md)
- **Gateway service:** [../gateway/README.md](../gateway/README.md)
- **General debugging:** [../../DEBUGGING-GUIDE.md](../../DEBUGGING-GUIDE.md)
- **Project overview:** [../../README-COMPLETE.md](../../README-COMPLETE.md)