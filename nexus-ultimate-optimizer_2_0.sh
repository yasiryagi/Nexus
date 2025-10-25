#!/bin/bash

# ================================================================
# NEXUS ULTIMATE OPTIMIZER v4.0 - STABLE BUILD
# Simplified compilation without conflicting flags
# 
# Key Features:
# - Simple, stable build configuration
# - 95% CPU usage
# - Modern nexus-network binary
# - No conflicting compiler flags
# ================================================================

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
INSTALL_DIR="/opt/nexus-ultimate"
REPO_DIR="$INSTALL_DIR/network-api"
CLI_DIR="$REPO_DIR/clients/cli"
BINARY_PATH="$INSTALL_DIR/nexus-network"

# Performance settings
MAX_THREADS_PER_NODE=2
DIFFICULTY_LEVEL="extra_large_4"

# Print banner
print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║        NEXUS ULTIMATE OPTIMIZER v4.0 - STABLE                    ║
║        Simplified Build for Maximum Compatibility                ║
║                                                                  ║
║  • 95% CPU Usage Target                                          ║
║  • Stable Compilation (No Flag Conflicts)                        ║
║  • Multi-node Deployment                                         ║
║  • Modern Nexus CLI                                              ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Logging functions
log_task() { echo -e "\n${BLUE}[TASK]${NC} $1"; }
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Install prerequisites
install_prerequisites() {
    log_task "Installing system packages"
    
    apt-get update > /dev/null 2>&1
    
    local packages=(
        "curl" "wget" "build-essential" "pkg-config" 
        "libssl-dev" "git" "screen" "htop" "jq" "bc"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "Installing $package..."
            apt-get install -y "$package" > /dev/null 2>&1
        fi
    done
}

# Install Rust
install_rust() {
    log_task "Setting up Rust"
    
    if ! command -v rustc &> /dev/null; then
        log_info "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
    
    source "$HOME/.cargo/env" 2>/dev/null || true
    export PATH="$HOME/.cargo/bin:$PATH"
    
    log_info "Rust version: $(rustc --version 2>/dev/null || echo 'checking...')"
}

# Install protobuf
install_protobuf() {
    log_task "Installing Protocol Buffers"
    
    if command -v protoc &> /dev/null; then
        log_info "Already installed: $(protoc --version)"
    else
        apt-get install -y protobuf-compiler > /dev/null 2>&1
        log_success "Protocol Buffers installed"
    fi
}

# Setup repository
setup_repository() {
    log_task "Setting up network-api repository"
    
    mkdir -p "$INSTALL_DIR"
    
    if [ -d "$REPO_DIR" ]; then
        log_info "Updating existing repository..."
        cd "$REPO_DIR"
        git fetch origin
        git reset --hard origin/main
    else
        log_info "Cloning repository..."
        cd "$INSTALL_DIR"
        git clone https://github.com/nexus-xyz/network-api.git
    fi
    
    log_success "Repository ready at $REPO_DIR"
}

# Compile with simple settings
compile_binary() {
    log_task "Compiling nexus-network binary"
    
    cd "$CLI_DIR"
    
    source "$HOME/.cargo/env" 2>/dev/null || true
    export PATH="$HOME/.cargo/bin:$PATH"
    
    log_info "Starting compilation (10-15 minutes)..."
    log_info "Using standard release profile"
    
    # Use simple release build without custom config
    if cargo build --release 2>&1 | tee /tmp/nexus-build.log; then
        
        # Find the binary
        if [ -f "target/release/nexus-network" ]; then
            cp target/release/nexus-network "$BINARY_PATH"
            chmod +x "$BINARY_PATH"
            
            local size=$(du -h "$BINARY_PATH" | cut -f1)
            log_success "✓ Compiled successfully: $BINARY_PATH ($size)"
            
            # Test it
            if "$BINARY_PATH" --help > /dev/null 2>&1; then
                log_success "✓ Binary is working"
                return 0
            else
                log_warning "Binary compiled but may have issues"
                return 0
            fi
        else
            log_error "Binary not found after compilation"
            log_info "Checking for available binaries..."
            ls -la target/release/ 2>/dev/null | grep -E '^-.*x' || true
            return 1
        fi
    else
        log_error "Compilation failed"
        log_error "Last 30 lines of build log:"
        echo ""
        tail -n 30 /tmp/nexus-build.log
        echo ""
        log_error "Full log: /tmp/nexus-build.log"
        return 1
    fi
}

# Create deployment scripts
create_deployment_scripts() {
    log_task "Creating deployment scripts"
    
    # Main start script
    cat > "$INSTALL_DIR/start-nodes.sh" << 'STARTSCRIPT'
#!/bin/bash

NUM_NODES=${1:-4}
BINARY="/opt/nexus-ultimate/nexus-network"
DIFFICULTY="extra_large_4"
MAX_THREADS=2

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Starting $NUM_NODES Nexus nodes...${NC}"

if [ ! -f "$HOME/.nexus/prover-id" ]; then
    echo -e "${YELLOW}No prover ID found. Random ID will be generated.${NC}"
    echo "To use your own ID:"
    echo "  mkdir -p ~/.nexus"
    echo "  echo 'YOUR_ID' > ~/.nexus/prover-id"
    echo ""
fi

for i in $(seq 1 $NUM_NODES); do
    SESSION="nexus-node-$i"
    
    if screen -list | grep -q "$SESSION"; then
        echo "Node $i already running"
        continue
    fi
    
    screen -dmS "$SESSION" bash -c "
        $BINARY start \
            --max-difficulty $DIFFICULTY \
            --max-threads $MAX_THREADS \
            2>&1 | tee -a /var/log/nexus-node-$i.log
    "
    
    echo -e "${GREEN}✓ Started node $i${NC}"
    sleep 2
done

echo ""
echo "Commands:"
echo "  screen -ls          # List sessions"
echo "  screen -r nexus-node-1    # Attach to node"
echo "  Ctrl+A then D       # Detach from screen"
STARTSCRIPT
    
    chmod +x "$INSTALL_DIR/start-nodes.sh"
    
    # Stop script
    cat > "$INSTALL_DIR/stop-nodes.sh" << 'STOPSCRIPT'
#!/bin/bash
echo "Stopping all Nexus nodes..."
screen -ls | grep nexus-node | cut -d. -f1 | awk '{print $1}' | xargs -r kill
echo "Done"
STOPSCRIPT
    
    chmod +x "$INSTALL_DIR/stop-nodes.sh"
    
    # Monitor script
    cat > "$INSTALL_DIR/monitor-nodes.sh" << 'MONITORSCRIPT'
#!/bin/bash
clear
echo "=== NEXUS NODES STATUS ==="
echo ""
screen -ls 2>/dev/null | grep nexus-node || echo "No nodes running"
echo ""
echo "System:"
echo "  CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
echo "  RAM: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
echo ""
echo "Commands:"
echo "  screen -r nexus-node-1    # View node"
echo "  tail -f /var/log/nexus-node-1.log    # View logs"
MONITORSCRIPT
    
    chmod +x "$INSTALL_DIR/monitor-nodes.sh"
    
    # Prover ID helper
    cat > "$INSTALL_DIR/setup-prover-id.sh" << 'IDSCRIPT'
#!/bin/bash
echo "Nexus Prover ID Setup"
echo ""
echo "Get your ID from: https://app.nexus.xyz"
echo "  → Nodes → Add Node → Add CLI Node"
echo ""
read -p "Enter your Prover ID: " PROVER_ID

mkdir -p ~/.nexus

if [ -n "$PROVER_ID" ]; then
    echo "$PROVER_ID" > ~/.nexus/prover-id
    echo "✓ Prover ID saved"
else
    echo "No ID entered. Random ID will be generated on first run."
fi
IDSCRIPT
    
    chmod +x "$INSTALL_DIR/setup-prover-id.sh"
    
    log_success "Scripts created"
}

# Detect CPU
detect_cpu() {
    log_task "System Information"
    
    local cpu=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    local cores=$(nproc)
    
    log_info "CPU: $cpu"
    log_info "Cores: $cores"
    
    local nodes=$((cores / 2))
    echo ""
    echo -e "${CYAN}Recommended: $nodes nodes (2 threads each)${NC}"
}

# Main
main() {
    print_banner
    
    check_root
    
    install_prerequisites
    
    install_rust
    
    install_protobuf
    
    setup_repository
    
    if compile_binary; then
        create_deployment_scripts
        detect_cpu
        
        echo ""
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✓ INSTALLATION COMPLETE                                  ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}Next Steps:${NC}"
        echo ""
        echo "1. Setup Prover ID:"
        echo "   ${YELLOW}cd $INSTALL_DIR && ./setup-prover-id.sh${NC}"
        echo ""
        echo "2. Start nodes:"
        echo "   ${YELLOW}cd $INSTALL_DIR && ./start-nodes.sh 4${NC}"
        echo ""
        echo "3. Monitor:"
        echo "   ${YELLOW}cd $INSTALL_DIR && ./monitor-nodes.sh${NC}"
        echo ""
        echo "Dashboard: https://app.nexus.xyz"
        echo ""
        
    else
        log_error "Installation failed"
        log_error "Check: /tmp/nexus-build.log"
        exit 1
    fi
}

main "$@"
