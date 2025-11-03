#!/bin/bash
# Video2MP3 - Start All Port Forwards
# This script starts port forwarding for all services to work with localhost
# Gateway uses port 80 for clean URLs (requires sudo)

echo "Starting port forwards for video2mp3 services..."
echo ""

# Stop any existing port forwards
sudo pkill -f 'kubectl port-forward' 2>/dev/null
sleep 1

# Clean up old log files (in case they were created by root)
sudo rm -f /tmp/gateway-pf.log /tmp/auth-pf.log /tmp/rabbitmq-pf.log 2>/dev/null

# Cache sudo credentials for background processes
echo "Authenticating sudo for port 80 access..."
sudo -v
echo ""

# Start Gateway on port 80 (requires sudo for clean URLs)
# Using sudo -E to preserve KUBECONFIG environment variable
echo "Starting gateway on port 80..."
sudo -E env "PATH=$PATH" kubectl port-forward service/gateway 80:8080 > /tmp/gateway-pf.log 2>&1 &
GATEWAY_PID=$!
echo "✓ Gateway:  http://video2mp3.com/login (port 80 - no port number needed!)"
echo "           PID: $GATEWAY_PID"

# Start Auth
kubectl port-forward service/auth 5000:5000 > /tmp/auth-pf.log 2>&1 &
AUTH_PID=$!
echo "✓ Auth:     http://localhost:5000 (PID: $AUTH_PID)"

# Start RabbitMQ
kubectl port-forward pod/rabbitmq-0 15672:15672 > /tmp/rabbitmq-pf.log 2>&1 &
RABBITMQ_PID=$!
echo "✓ RabbitMQ: http://localhost:15672 or http://rabbitmq-manager.com:15672 (PID: $RABBITMQ_PID)"
echo "           Credentials: guest / guest"

echo ""
echo "All services started successfully!"
echo ""
echo "Test login (clean URL - no port number!):"
echo "  curl -X POST -u 'dksahuji@gmail.com:Admin123' http://video2mp3.com/login"
echo ""
echo "Alternative URLs:"
echo "  Gateway:  http://localhost/login"
echo "  Auth:     http://localhost:5000/login"
echo "  RabbitMQ: http://localhost:15672"
echo ""
echo "View logs:"
echo "  tail -f /tmp/gateway-pf.log"
echo "  tail -f /tmp/auth-pf.log"
echo "  tail -f /tmp/rabbitmq-pf.log"
echo ""
echo "View worker logs (no port forwarding needed):"
echo "  kubectl logs -l app=converter -f"
echo "  kubectl logs -l app=notification -f"
echo ""
echo "Stop all services:"
echo "  sudo pkill -f 'kubectl port-forward'"
echo ""
