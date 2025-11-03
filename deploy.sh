#!/bin/bash
# deploy.sh - Deploy video2mp3 to Kubernetes with auto-detected host IP

set -e

echo "🚀 Deploying video2mp3 to Kubernetes..."
./start-services.sh

# Auto-detect minikube host IP
if command -v minikube &> /dev/null; then
    # Get minikube IP and calculate host IP (usually .1 in the same subnet)
    MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "")
    if [ -n "$MINIKUBE_IP" ]; then
        # Extract first three octets and append .1
        HOST_IP=$(echo "$MINIKUBE_IP" | sed 's/\.[0-9]*$/.1/')
        echo "✓ Detected minikube host IP: $HOST_IP"
    else
        echo "⚠ Could not detect minikube IP, using default: 192.168.49.1"
        HOST_IP="192.168.49.1"
    fi
else
    echo "⚠ minikube not found, using default host IP: 192.168.49.1"
    HOST_IP="192.168.49.1"
fi

# Export variables for envsubst
export MYSQL_HOST="$HOST_IP"
export MONGODB_HOST="$HOST_IP"
export MYSQL_PORT="3306"
export MONGODB_PORT="27017"
export $(< .env)

echo ""
echo "📝 Configuration:"
echo "   MYSQL_HOST=$MYSQL_HOST"
echo "   MONGODB_HOST=$MONGODB_HOST"
echo ""

# Deploy auth service
echo "Deploying auth service..."
envsubst < src/auth/manifests/configmap.yaml.template | kubectl apply -f -
kubectl apply -f src/auth/manifests/secret.yaml
kubectl apply -f src/auth/manifests/auth-deploy.yaml
kubectl apply -f src/auth/manifests/service.yaml

# Deploy gateway service
echo "Deploying gateway service..."
envsubst < src/gateway/manifests/configmap.yaml.template | kubectl apply -f -
kubectl apply -f src/gateway/manifests/secret.yaml
kubectl apply -f src/gateway/manifests/gateway-deploy.yaml
kubectl apply -f src/gateway/manifests/service.yaml
kubectl apply -f src/gateway/manifests/ingress.yaml

# Deploy RabbitMQ
echo "Deploying RabbitMQ..."
kubectl apply -f src/rabbitMQ/manifests/

# Deploy converter
echo "Deploying converter..."
if [ -d "src/converter/manifests" ]; then
    envsubst < src/converter/manifests/configmap.yaml.template | kubectl apply -f -
    kubectl apply -f src/converter/manifests/secret.yaml
    kubectl apply -f src/converter/manifests/converter-deploy.yaml
fi


# Deploy notification service
echo "Deploying notification service..."
envsubst < src/notification/manifests/secret.yaml.template | kubectl apply -f -
kubectl apply -f src/notification/manifests/notification-deploy.yaml
kubectl apply -f src/notification/manifests/configmap.yaml

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/auth --timeout=60s
kubectl rollout status deployment/gateway --timeout=60s

echo ""
echo "🎉 All services deployed successfully!"
echo ""
echo "Next steps:"
echo "  1. Start port forwarding: ./start-services.sh"
echo "  2. Test login: curl -X POST -u 'dksahuji@gmail.com:Admin123' http://video2mp3.com/login"
