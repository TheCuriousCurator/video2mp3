#!/bin/bash
# setup-host.sh - Prepare host machine (MySQL/MongoDB) for Kubernetes access

set -e

echo "🔧 Setting up host machine for video2mp3 Kubernetes access..."
echo ""

# Auto-detect minikube subnet
if command -v minikube &> /dev/null; then
    MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "")
    if [ -n "$MINIKUBE_IP" ]; then
        # Extract subnet (e.g., 192.168.49.2 -> 192.168.49)
        MINIKUBE_SUBNET=$(echo "$MINIKUBE_IP" | sed 's/\.[0-9]*$//')
        HOST_IP="${MINIKUBE_SUBNET}.1"
        echo "✓ Detected minikube subnet: ${MINIKUBE_SUBNET}.0/24"
        echo "✓ Detected host IP: $HOST_IP"
    else
        echo "⚠ Could not detect minikube IP, using default: 192.168.49"
        MINIKUBE_SUBNET="192.168.49"
        HOST_IP="192.168.49.1"
    fi
else
    echo "⚠ minikube not found, using default subnet: 192.168.49"
    MINIKUBE_SUBNET="192.168.49"
    HOST_IP="192.168.49.1"
fi

echo ""
echo "📝 Configuration:"
echo "   Minikube Subnet: ${MINIKUBE_SUBNET}.%"
echo "   Host IP: $HOST_IP"
echo ""

# ============================================
# MySQL Setup
# ============================================
echo "🗄️  Configuring MySQL..."

# Check if MySQL is installed
if ! command -v mysql &> /dev/null; then
    echo "❌ MySQL not found. Please install MySQL first:"
    echo "   sudo apt-get install mysql-server"
    exit 1
fi

# Check if MySQL is running
if ! sudo systemctl is-active --quiet mysql 2>/dev/null; then
    echo "⚠️  MySQL is not running. Starting MySQL..."
    sudo systemctl start mysql
fi

echo "✓ MySQL is running"

# Check and update bind-address
echo ""
echo "Checking MySQL bind-address..."
CURRENT_BIND=$(grep -E "^bind-address" /etc/mysql/mysql.conf.d/mysqld.cnf 2>/dev/null || echo "")

if [ -z "$CURRENT_BIND" ]; then
    echo "⚠️  No bind-address found in config"
elif echo "$CURRENT_BIND" | grep -q "127.0.0.1"; then
    echo "⚠️  MySQL is bound to localhost only: $CURRENT_BIND"
    echo "   Updating to bind to all interfaces (0.0.0.0)..."

    # Backup config
    sudo cp /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf.backup.$(date +%Y%m%d_%H%M%S)

    # Update bind-address
    sudo sed -i 's/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

    echo "✓ Updated bind-address to 0.0.0.0"
    echo "   Restarting MySQL..."
    sudo systemctl restart mysql
    sleep 2
    echo "✓ MySQL restarted"
elif echo "$CURRENT_BIND" | grep -q "0.0.0.0"; then
    echo "✓ MySQL already bound to all interfaces"
else
    echo "ℹ️  Custom bind-address: $CURRENT_BIND"
fi

# Verify MySQL is listening
echo ""
echo "Verifying MySQL is listening on $HOST_IP:3306..."
if ss -tlnp 2>/dev/null | grep -q ":3306.*0.0.0.0"; then
    echo "✓ MySQL is listening on 0.0.0.0:3306"
elif ss -tlnp 2>/dev/null | grep -q ":3306"; then
    echo "⚠️  MySQL is listening, but not on 0.0.0.0"
    ss -tlnp 2>/dev/null | grep ":3306"
else
    echo "❌ MySQL not listening on port 3306"
fi

# Create/update MySQL user permissions
echo ""
echo "Setting up MySQL user permissions for minikube..."
echo "   User: auth_user"
echo "   Host pattern: ${MINIKUBE_SUBNET}.%"
echo "   Database: auth"
echo ""

# Run MySQL commands
sudo mysql -u root << EOF
-- Create user for minikube subnet if not exists
CREATE USER IF NOT EXISTS 'auth_user'@'${MINIKUBE_SUBNET}.%' IDENTIFIED BY 'Auth123';

-- Grant all privileges on auth database
GRANT ALL PRIVILEGES ON auth.* TO 'auth_user'@'${MINIKUBE_SUBNET}.%';

-- Flush privileges
FLUSH PRIVILEGES;

-- Show current auth_user permissions
SELECT User, Host FROM mysql.user WHERE User='auth_user';
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ MySQL user 'auth_user'@'${MINIKUBE_SUBNET}.%' configured successfully"
else
    echo ""
    echo "❌ Failed to configure MySQL user"
    exit 1
fi

# ============================================
# MongoDB Setup
# ============================================
echo ""
echo "🍃 Configuring MongoDB..."

# Check if MongoDB is installed
if ! command -v mongod &> /dev/null && ! command -v mongosh &> /dev/null; then
    echo "⚠️  MongoDB not found. Skipping MongoDB setup."
    echo "   Install MongoDB if needed: sudo apt-get install mongodb-org"
else
    # Check if MongoDB is running
    if ! sudo systemctl is-active --quiet mongod 2>/dev/null; then
        echo "⚠️  MongoDB is not running. Starting MongoDB..."
        sudo systemctl start mongod 2>/dev/null || echo "Could not start MongoDB automatically"
    else
        echo "✓ MongoDB is running"
    fi

    # Check MongoDB bind address
    echo ""
    echo "Checking MongoDB bind address..."
    if [ -f /etc/mongod.conf ]; then
        MONGO_BIND=$(grep -E "^\s*bindIp:" /etc/mongod.conf | awk '{print $2}')

        if [ "$MONGO_BIND" = "127.0.0.1" ]; then
            echo "⚠️  MongoDB bound to localhost only"
            echo "   Updating to bind to all interfaces (0.0.0.0)..."

            # Backup config
            sudo cp /etc/mongod.conf /etc/mongod.conf.backup.$(date +%Y%m%d_%H%M%S)

            # Update bindIp
            sudo sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf

            echo "✓ Updated bindIp to 0.0.0.0"
            echo "   Restarting MongoDB..."
            sudo systemctl restart mongod
            sleep 2
            echo "✓ MongoDB restarted"
        elif [ "$MONGO_BIND" = "0.0.0.0" ]; then
            echo "✓ MongoDB already bound to all interfaces"
        else
            echo "ℹ️  Custom bindIp: $MONGO_BIND"
        fi
    else
        echo "⚠️  MongoDB config file not found at /etc/mongod.conf"
    fi

    # Verify MongoDB is listening
    echo ""
    echo "Verifying MongoDB is listening on $HOST_IP:27017..."
    if ss -tlnp 2>/dev/null | grep -q ":27017.*0.0.0.0"; then
        echo "✓ MongoDB is listening on 0.0.0.0:27017"
    elif ss -tlnp 2>/dev/null | grep -q ":27017"; then
        echo "⚠️  MongoDB is listening, but not on 0.0.0.0"
        ss -tlnp 2>/dev/null | grep ":27017"
    else
        echo "⚠️  MongoDB not listening on port 27017"
    fi

    echo ""
    echo "ℹ️  Note: MongoDB is running without authentication (development mode)"
    echo "   No user setup needed - Kubernetes pods can connect directly"
fi

# ============================================
# Verification
# ============================================
echo ""
echo "🔍 Verification..."
echo ""

# Test MySQL connectivity from host
echo "Testing MySQL connectivity from host..."
if mysql -u auth_user -pAuth123 -h $HOST_IP -e "SELECT 1;" &> /dev/null; then
    echo "✓ MySQL connection successful from host"
else
    echo "❌ MySQL connection failed from host"
    echo "   Try: mysql -u auth_user -pAuth123 -h $HOST_IP"
fi

# Check if kubectl/minikube is available for pod testing
if command -v kubectl &> /dev/null && kubectl get nodes &> /dev/null; then
    echo ""
    echo "Testing connectivity from Kubernetes pods..."

    # Test from auth pod if it exists
    if kubectl get deployment auth &> /dev/null; then
        echo "Testing MySQL from auth pod..."
        if kubectl exec deployment/auth -- mysql -u auth_user -pAuth123 -h $HOST_IP auth -e "SELECT 1;" &> /dev/null 2>&1; then
            echo "✓ MySQL connection successful from auth pod"
        else
            echo "⚠️  MySQL connection failed from auth pod (pod may not be ready yet)"
        fi
    fi

    # Test from gateway pod if it exists
    if kubectl get deployment gateway &> /dev/null; then
        echo "Testing MongoDB from gateway pod..."
        if kubectl exec deployment/gateway -- python3 -c "import pymongo; pymongo.MongoClient('mongodb://$HOST_IP:27017/').server_info()" &> /dev/null 2>&1; then
            echo "✓ MongoDB connection successful from gateway pod"
        else
            echo "⚠️  MongoDB connection failed from gateway pod (pod may not be ready yet)"
        fi
    fi
else
    echo ""
    echo "ℹ️  Kubernetes not available - skipping pod connectivity tests"
    echo "   Deploy with ./deploy.sh and test connectivity"
fi

# ============================================
# Summary
# ============================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Host setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Summary:"
echo "   • MySQL user: auth_user@${MINIKUBE_SUBNET}.%"
echo "   • MySQL listening: 0.0.0.0:3306"
echo "   • MongoDB listening: 0.0.0.0:27017"
echo "   • Host IP: $HOST_IP"
echo ""
echo "Next steps:"
echo "   1. Deploy services:     ./deploy.sh"
echo "   2. Start port forwards: ./start-services.sh"
echo "   3. Test login:          curl -X POST -u 'dksahuji@gmail.com:Admin123' http://video2mp3.com/login"
echo ""
echo "💡 Tip: Run this script again if your minikube IP changes"
echo ""
