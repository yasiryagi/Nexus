FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

# Install all required packages
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    curl \
    build-essential \
    pkg-config \
    libssl-dev \
    git \
    openssl \
    ca-certificates \
    protobuf-compiler \
    procps \
    coreutils \
    util-linux \
    screen \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:$PATH"

# Install Nexus to /opt/nexus instead of /root/.nexus
RUN curl -L https://cli.nexus.xyz/ -o /root/install.sh
RUN chmod +x /root/install.sh
RUN cd /root && echo "y" | bash install.sh

# Copy nexus binary to /usr/local/bin so it's always available
RUN cp /root/.nexus/bin/nexus-network /usr/local/bin/nexus-network
RUN chmod +x /usr/local/bin/nexus-network

# Verify installation
RUN nexus-network --help

# Create logs directory
RUN mkdir -p /root/logs

CMD ["/bin/bash"]
