# Video2MP3 Microservices Project

A production-ready microservices architecture for converting video files to MP3 format, built with Python, Kubernetes, RabbitMQ, and featuring JWT authentication.

## Architecture Overview

This project demonstrates a complete microservices system with:

- **Gateway Service** (Flask) - API entry point, file upload/download, message publishing
- **Auth Service** (Flask) - JWT-based authentication and validation
- **Converter Service** (Python) - Asynchronous video-to-MP3 processing workers (4 replicas)
- **RabbitMQ** - Message queue for asynchronous task management
- **MySQL** - User authentication database (host machine)
- **MongoDB** - Video/MP3 file storage using GridFS (host machine)

## Tech Stack

- **Python 3.12** with Flask, PyJWT, MoviePy, Pika, PyMongo
- **Kubernetes (Minikube)** for container orchestration
- **Docker** for containerization
- **RabbitMQ** for message queuing
- **MySQL 8.0** for authentication data
- **MongoDB** with GridFS for file storage
- **FFmpeg** for audio extraction

## Quick Start

```bash
# 1. Setup host databases (first time only)
./setup-host.sh

# 2. Deploy all services to Kubernetes
./deploy.sh

# 3. Start port forwarding for local access
./start-services.sh

# 4. Test the system
curl -X POST -u "dksahuji@gmail.com:Admin123" http://video2mp3.com/login
```

## Documentation

- **[QUICKSTART.md](./QUICKSTART.md)** - Get running in 4 commands
- **[README-COMPLETE.md](./README-COMPLETE.md)** - Comprehensive guide and architecture details
- **[DEPLOYMENT.md](./DEPLOYMENT.md)** - Deployment options and configuration
- **[DEBUGGING-GUIDE.md](./DEBUGGING-GUIDE.md)** - Troubleshooting and debugging methodologies
- **[DOCUMENTATION-INDEX.md](./DOCUMENTATION-INDEX.md)** - Complete documentation index

## Helper Scripts

| Script | Purpose |
|--------|---------|
| `./setup-host.sh` | Configure MySQL/MongoDB for Kubernetes access (run once) |
| `./deploy.sh` | Deploy all services to Kubernetes |
| `./undeploy.sh` | Remove all services from Kubernetes |
| `./start-services.sh` | Start port forwarding for local development |
| `./run-demo.sh` | Complete end-to-end demo |

## Service URLs

With `./start-services.sh` running:

- **Gateway**: http://video2mp3.com/login
- **RabbitMQ Management**: http://localhost:15672 (guest/guest)
- **Auth Service**: http://localhost:5000

## Prerequisites

```bash
# System requirements
sudo apt-get install libmysqlclient-dev

# Required services
- Docker and Kubernetes (minikube)
- MySQL 8.0 running on host machine
- MongoDB running on host machine
- kubectl configured for minikube cluster
```

## Project Structure

```
video2mp3/
├── src/
│   ├── auth/          # JWT authentication service
│   ├── gateway/       # API gateway and file handling
│   ├── converter/     # Video-to-MP3 conversion workers
│   └── rabbitMQ/      # Message queue configuration
├── deploy.sh          # Automated deployment
├── setup-host.sh      # Database configuration
├── start-services.sh  # Port forwarding setup
└── Documentation files...
```

## Default Credentials

- **Test User**: dksahuji@gmail.com / Admin123
- **RabbitMQ**: guest / guest

## Contributing

See [README-COMPLETE.md](./README-COMPLETE.md) for development workflow and contributing guidelines.

## License

MIT License
