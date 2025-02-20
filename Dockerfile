FROM ubuntu:latest

# Define the build argument and environment variable for NODE_ID
ARG NODE_ID
ENV NODE_ID=${NODE_ID:-""}

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    curl \
    git \
    openssl \
    ca-certificates \
    protobuf-compiler \
    tmux

# Install Rust and add RISC-V target
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs/ | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN rustup target add riscv32i-unknown-none-elf

# Download and prepare Nexus setup
RUN curl https://cli.nexus.xyz/ > setup.sh && \
    chmod +x setup.sh

# Create startup script
RUN echo '#!/bin/bash\n\
rm -rf ~/.nexus\n\
tmux new-session -d -s nexus "./setup.sh"\n\
sleep 2\n\
tmux send-keys -t nexus "y" Enter\n\
sleep 2\n\
tmux send-keys -t nexus "2" Enter\n\
sleep 2\n\
tmux send-keys -t nexus "$NODE_ID" Enter\n\
tail -f /dev/null' > /root/start.sh && \
    chmod +x /root/start.sh

# Set the entry point
ENTRYPOINT ["/root/start.sh"]
