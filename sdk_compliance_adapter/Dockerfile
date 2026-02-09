# Build stage
FROM swift:5.9 as builder

# Install zlib development headers
RUN apt-get update && apt-get install -y zlib1g-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the entire PostHog iOS SDK
COPY . /app/

# Navigate to the adapter directory
WORKDIR /app/sdk_compliance_adapter

# Resolve dependencies
RUN swift package resolve

# Build the adapter with custom module map for zlibLinux and TESTING flag
# This allows the iOS SDK's Data+Gzip.swift to compile on Linux
# TESTING flag prevents Bundle.main.bundleIdentifier! crash in command-line environment
RUN swift build -c release -Xcc -I/app/sdk_compliance_adapter/InternalModules/zlibLinux -Xswiftc -DTESTING

# Runtime stage
FROM swift:5.9-slim

WORKDIR /app

# Copy the built executable
COPY --from=builder /app/sdk_compliance_adapter/.build/release/PostHogIOSComplianceAdapter /app/adapter

# Expose port 8080
EXPOSE 8080

# Set environment variables
ENV HOSTNAME=0.0.0.0
ENV PORT=8080

# Run the adapter
CMD ["/app/adapter", "serve", "--hostname", "0.0.0.0", "--port", "8080"]
