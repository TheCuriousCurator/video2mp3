# Converter Service

Asynchronous video-to-MP3 conversion workers for the video2mp3 microservices system.

## Overview

The Converter service provides:
- RabbitMQ consumer that listens for video conversion jobs
- Video-to-MP3 conversion using MoviePy and FFmpeg
- MongoDB GridFS integration for video/MP3 storage
- Scalable worker architecture (4 replicas by default)
- Automatic message acknowledgment and error handling

## Architecture

```
RabbitMQ "video" queue
    �
Converter Workers (4 replicas)
    � MongoDB:27017 (retrieve video)
    � FFmpeg (extract audio)
    � MongoDB:27017 (store MP3)
    � RabbitMQ "mp3" queue (publish completion)
```

## How It Works

### Conversion Flow

1. **Consume Message** - Worker listens on RabbitMQ `video` queue
2. **Retrieve Video** - Fetch video from MongoDB using `video_fid`
3. **Extract Audio** - Use MoviePy to extract audio and convert to MP3
4. **Store MP3** - Save MP3 file to MongoDB GridFS
5. **Publish Result** - Send completion message to `mp3` queue with `mp3_fid`
6. **Acknowledge** - ACK message to RabbitMQ (or NACK on failure)

### Message Format

**Input (from "video" queue):**
```json
{
  "video_fid": "<MongoDB ObjectId>",
  "mp3_fid": null,
  "username": "dksahuji@gmail.com"
}
```

**Output (to "mp3" queue):**
```json
{
  "video_fid": "<MongoDB ObjectId>",
  "mp3_fid": "<MongoDB ObjectId>",
  "username": "dksahuji@gmail.com"
}
```

## Components

### consumer.py
Main consumer loop that:
- Connects to RabbitMQ
- Consumes messages from `video` queue
- Calls `to_mp3.start()` for each message
- Handles acknowledgments (ACK/NACK)
- Implements error handling and retry logic

### convert/to_mp3.py
Conversion logic that:
- Retrieves video from MongoDB GridFS by `video_fid`
- Writes video to temporary file
- Uses MoviePy to extract audio track
- Saves audio as MP3 to temporary file
- Stores MP3 in MongoDB GridFS
- Publishes result to `mp3` queue with `mp3_fid`
- Cleans up temporary files

## Configuration

### Environment Variables (ConfigMap)
- `MONGODB_HOST` - MongoDB host IP (e.g., 192.168.49.1 for minikube)
- `MONGODB_PORT` - MongoDB port (27017)
- `VIDEO_QUEUE` - RabbitMQ queue name for incoming videos (default: "video")
- `MP3_QUEUE` - RabbitMQ queue name for completed MP3s (default: "mp3")

### Secrets
- MongoDB credentials (if authentication enabled)
- RabbitMQ credentials

## Docker Build & Deploy

### Build Docker Image
```bash
cd src/converter
docker build -t dksahuji/video2mp3-converter:latest .
```

**Note:** Dockerfile includes FFmpeg binary installation for audio processing.

### Push to Docker Hub
```bash
docker push dksahuji/video2mp3-converter:latest
```

## Kubernetes Deployment

### Deploy Converter Service
```bash
cd src/converter/manifests
kubectl apply -f ./
```

This creates:
- `deployment.apps/converter` - 4 replicas for parallel processing
- `configmap/converter-configmap` - Environment configuration
- `secret/converter-secret` - Sensitive credentials

### Undeploy
```bash
kubectl delete -f ./
```

### Scale Workers
```bash
# Scale to 8 workers for higher throughput
kubectl scale deployment converter --replicas=8

# Check workers
kubectl get pods -l app=converter
```

**Scaling Strategy:**
- More workers = more parallel conversions
- Each worker processes one video at a time
- RollingUpdate strategy with maxSurge: 8

## Monitoring & Debugging

### Check Deployment Status
```bash
# View pods
kubectl get pods -l app=converter

# View logs from all workers
kubectl logs -l app=converter --tail=50 -f

# View logs from specific pod
kubectl logs <pod-name> -f
```

### Shell into Worker Pod
```bash
kubectl exec -it deployment/converter -- /bin/bash

# Test MongoDB connection
python3 -c "import pymongo; print(pymongo.MongoClient('mongodb://192.168.49.1:27017/').server_info())"

# Check FFmpeg is installed
ffmpeg -version

# Test MoviePy
python3 -c "import moviepy; print(moviepy.__version__)"
```

### Monitor RabbitMQ Queue
```bash
# Port forward to RabbitMQ Management UI
kubectl port-forward pod/rabbitmq-0 15672:15672

# Open browser: http://localhost:15672
# Login: guest / guest
# Check "video" queue for pending messages
```

## Common Issues

### Worker Crashes During Conversion
**Problem:** Out of memory or FFmpeg errors

**Check logs:**
```bash
kubectl logs <pod-name>
```

**Solutions:**
- Increase pod memory limits in converter-deploy.yaml
- Check video format compatibility
- Verify FFmpeg is properly installed

### Can't Connect to MongoDB
**Problem:** MongoDB not accessible from pods

**Test connection:**
```bash
kubectl exec deployment/converter -- python3 -c \
  "import pymongo; pymongo.MongoClient('mongodb://192.168.49.1:27017/').server_info()"
```

**Solution:** Ensure MongoDB bind IP is 0.0.0.0 (see setup-host.sh)

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
kubectl exec deployment/converter -- python3 -c \
  "import pika; conn = pika.BlockingConnection(pika.ConnectionParameters('rabbitmq')); print('Connected')"
```

### Temporary Files Not Cleaned Up
**Problem:** Disk space issues

**Check disk usage:**
```bash
kubectl exec deployment/converter -- df -h
```

**Solution:** to_mp3.py should clean up temp files automatically. Check logs for errors during cleanup.

## Performance Tuning

### Worker Count
- **4 workers (default):** Good for moderate load
- **8 workers:** High throughput scenarios
- **16+ workers:** Very high load (ensure sufficient cluster resources)

### Resource Limits
Edit `converter-deploy.yaml`:
```yaml
resources:
  limits:
    memory: "1Gi"  # Increase for large videos
    cpu: "1000m"
  requests:
    memory: "512Mi"
    cpu: "500m"
```

### Queue Prefetch
In consumer.py, adjust prefetch_count:
```python
channel.basic_qos(prefetch_count=1)  # Process one message at a time per worker
```

## Conversion Logic Details

### MoviePy Pipeline
1. `VideoFileClip(temp_video_path)` - Load video
2. `video.audio.write_audiofile(temp_mp3_path)` - Extract and encode audio
3. Automatically uses FFmpeg for encoding

### Temporary File Management
- Video: Uses Python's `tempfile.NamedTemporaryFile()` (auto-deleted on close)
- MP3: `/tmp/<video_fid>.mp3`
- MP3 files cleaned up with `os.remove()` after successful MongoDB upload
- Error handling: If publish to mp3 queue fails, deletes the mp3 file from MongoDB

### Error Handling
- If conversion fails: NACK message (returns to queue)
- If MongoDB upload fails: Cleanup temp files, NACK message
- If RabbitMQ publish to mp3 queue fails: Deletes MP3 from MongoDB, returns error (causes NACK)

## Files

- `consumer.py` - RabbitMQ consumer loop and message handling
- `convert/to_mp3.py` - Video-to-MP3 conversion logic
- `Dockerfile` - Python 3.12-slim with FFmpeg
- `pyproject.toml` - Dependencies: moviepy, pika, pymongo
- `manifests/` - Kubernetes deployment files
  - `converter-deploy.yaml` - Deployment with 4 replicas
  - `configmap.yaml.template` - Environment variables (uses ${MONGODB_HOST})
  - `secret.yaml` - Sensitive credentials

## Development Workflow

```bash
# 1. Make code changes
vim consumer.py
vim convert/to_mp3.py

# 2. Rebuild Docker image
docker build -t dksahuji/video2mp3-converter:latest .
docker push dksahuji/video2mp3-converter:latest

# 3. Restart deployment
kubectl rollout restart deployment/converter
kubectl rollout status deployment/converter

# 4. Monitor logs
kubectl logs -l app=converter --tail=50 -f

# 5. Test conversion
# Upload a video via gateway and watch worker logs
```

## Testing

### End-to-End Test
```bash
# 1. Upload video
TOKEN=$(curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login 2>/dev/null)
curl -X POST -F "file=@test.mp4" \
  -H "Authorization: Bearer $TOKEN" \
  http://video2mp3.com/upload

# 2. Watch converter logs
kubectl logs -l app=converter -f

# 3. Check RabbitMQ (should see message processed)
# Open http://localhost:15672 and check queues

# 4. Download MP3 (after conversion completes)
curl -X GET "http://video2mp3.com/download?fid=<mp3_fid>" \
  -H "Authorization: Bearer $TOKEN" \
  -o output.mp3
```

## Resources

- [MoviePy Documentation](https://zulko.github.io/moviepy/)
- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [Pika (RabbitMQ) Documentation](https://pika.readthedocs.io/)
- [MongoDB GridFS](https://www.mongodb.com/docs/manual/core/gridfs/)
- [RabbitMQ Tutorials](https://www.rabbitmq.com/getstarted.html)

## Related Documentation

- **RabbitMQ setup:** [../rabbitMQ/README.md](../rabbitMQ/README.md)
- **General debugging:** [../../DEBUGGING-GUIDE.md](../../DEBUGGING-GUIDE.md)
- **Project overview:** [../../README-COMPLETE.md](../../README-COMPLETE.md)
