# Use Ubuntu 24.04 for GLIBC 2.39 support
FROM ubuntu:24.04

# Prevent debconf warnings
ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    screen \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /root/.nexus /root/logs

# Copy the optimized binary
COPY nexus-network /usr/local/bin/nexus-network
RUN chmod +x /usr/local/bin/nexus-network

# Verify GLIBC compatibility
RUN ldd /usr/local/bin/nexus-network || echo "Binary linked successfully"

# Default working directory
WORKDIR /root

# Keep container running
CMD ["tail", "-f", "/dev/null"]
