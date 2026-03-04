#!/bin/bash
set -e

# PostHog iOS SDK Compliance Test Runner
# This script runs the compliance tests using the Hybrid Runner architecture

echo "🚀 PostHog iOS SDK Compliance Test Runner"
echo "=========================================="
echo ""

# Check prerequisites
if ! command -v swift &> /dev/null; then
    echo "❌ Error: Swift not found. Please install Swift 5.9+"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Error: Docker not running. Please start Docker Desktop"
    exit 1
fi

# Build the adapter with TESTING flag (debug mode is faster)
echo "📦 Building iOS adapter..."
swift build -Xswiftc -DTESTING
echo "✅ Adapter built successfully"
echo ""

# Start the adapter in the background with logging
ADAPTER_LOG="adapter_$(date +%Y%m%d_%H%M%S).log"
echo "🏃 Starting adapter on port 8080..."
echo "📝 Adapter logs: $ADAPTER_LOG"
.build/debug/PostHogIOSComplianceAdapter serve --hostname 0.0.0.0 --port 8080 > "$ADAPTER_LOG" 2>&1 &
ADAPTER_PID=$!

# Wait for adapter to start
echo "⏳ Waiting for adapter to start..."
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo "✅ Adapter is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Error: Adapter failed to start"
        kill $ADAPTER_PID 2>/dev/null || true
        exit 1
    fi
    sleep 1
done
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "🧹 Cleaning up..."
    kill $ADAPTER_PID 2>/dev/null || true
    docker-compose down 2>/dev/null || true
    echo "✅ Cleanup complete"
}
trap cleanup EXIT

# Run the tests
echo "🧪 Running compliance tests..."
echo ""
docker-compose up --abort-on-container-exit

echo ""
echo "🎉 Tests complete!"
echo ""
echo "📋 Adapter log (last 50 lines):"
echo "================================"
tail -50 "$ADAPTER_LOG"
