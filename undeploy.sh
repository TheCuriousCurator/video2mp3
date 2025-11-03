#!/bin/bash
# undeploy.sh - Remove all video2mp3 services from Kubernetes

set -e

echo "🗑️  Undeploying video2mp3 from Kubernetes..."
echo ""

# Function to safely delete resources
safe_delete() {
    local resource_type=$1
    local resource_name=$2

    if kubectl get "$resource_type" "$resource_name" &> /dev/null; then
        echo "  Deleting $resource_type/$resource_name..."
        kubectl delete "$resource_type" "$resource_name" --ignore-not-found=true
    else
        echo "  $resource_type/$resource_name not found (skipping)"
    fi
}

# Stop port forwards first
echo "Stopping port forwards..."
sudo pkill -f 'kubectl port-forward' 2>/dev/null || true
echo "✓ Port forwards stopped"
echo ""

# Delete notification
echo "Undeploying notification..."
safe_delete deployment notification
safe_delete configmap notification-configmap
safe_delete secret notification-secret
echo "✓ Notification removed"
echo ""

# Delete converter
echo "Undeploying converter..."
safe_delete deployment converter
safe_delete configmap converter-configmap
safe_delete secret converter-secret
echo "✓ Converter removed"
echo ""

# Delete gateway
echo "Undeploying gateway..."
safe_delete deployment gateway
safe_delete service gateway
safe_delete configmap gateway-configmap
safe_delete secret gateway-secret
safe_delete ingress gateway-ingress
echo "✓ Gateway removed"
echo ""

# Delete auth
echo "Undeploying auth..."
safe_delete deployment auth
safe_delete service auth
safe_delete configmap auth-configmap
safe_delete secret auth-secret
echo "✓ Auth removed"
echo ""

# Delete RabbitMQ
echo "Undeploying RabbitMQ..."
safe_delete statefulset rabbitmq
safe_delete service rabbitmq
safe_delete configmap rabbitmq-configmap
safe_delete secret rabbitmq-secret
safe_delete ingress rabbitmq-ingress
safe_delete pvc rabbitmq-pvc
echo "✓ RabbitMQ removed"
echo ""

# Check for any remaining resources
echo "Checking for remaining resources..."
echo ""

REMAINING_DEPLOYMENTS=$(kubectl get deployments -l 'app in (auth,gateway,converter,notification)' --no-headers 2>/dev/null | wc -l)
REMAINING_SERVICES=$(kubectl get services -l 'app in (auth,gateway,rabbitmq)' --no-headers 2>/dev/null | wc -l)
REMAINING_STATEFULSETS=$(kubectl get statefulsets -l 'app=rabbitmq' --no-headers 2>/dev/null | wc -l)

if [ "$REMAINING_DEPLOYMENTS" -gt 0 ] || [ "$REMAINING_SERVICES" -gt 0 ] || [ "$REMAINING_STATEFULSETS" -gt 0 ]; then
    echo "⚠️  Some resources still remain:"
    [ "$REMAINING_DEPLOYMENTS" -gt 0 ] && kubectl get deployments -l 'app in (auth,gateway,converter,notification)'
    [ "$REMAINING_SERVICES" -gt 0 ] && kubectl get services -l 'app in (auth,gateway,rabbitmq)'
    [ "$REMAINING_STATEFULSETS" -gt 0 ] && kubectl get statefulsets -l 'app=rabbitmq'
    echo ""
    echo "You may need to delete these manually:"
    echo "  kubectl delete deployment <name>"
    echo "  kubectl delete service <name>"
    echo "  kubectl delete statefulset <name>"
else
    echo "✓ All video2mp3 resources removed successfully!"
fi

echo ""
echo "📝 Note: This script does NOT remove:"
echo "   - Docker images (use: docker rmi <image>)"
echo "   - MySQL/MongoDB data on host machine"
echo "   - PersistentVolume claims (deleted PVC only)"
echo ""
echo "🎉 Undeployment complete!"
