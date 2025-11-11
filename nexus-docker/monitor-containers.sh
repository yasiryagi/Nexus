#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

CONTAINER_PREFIX="nexus"

clear
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    NEXUS OPTIMIZED CONTAINERS - LIVE STATUS               ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "$(date) - CPU: 95% | RAM: 90% | EL5: Unlocked"
echo ""

CONTAINERS=$(sudo docker ps -a --filter "name=$CONTAINER_PREFIX-" --format "{{.Names}}" | sort)

if [ -z "$CONTAINERS" ]; then
    echo -e "${RED}❌ No containers found${NC}"
    exit 0
fi

RUNNING=0
STOPPED=0

for CONTAINER in $CONTAINERS; do
    echo -e "${CYAN}━━━ $CONTAINER ━━━${NC}"
    
    if sudo docker ps --filter "name=$CONTAINER" | grep -q "$CONTAINER"; then
        ((RUNNING++))
        STATS=$(sudo docker stats --no-stream --format "CPU: {{.CPUPerc}} | RAM: {{.MemUsage}}" "$CONTAIN
ER")
        echo -e "  Status:    ${GREEN}✅ Running (Optimized)${NC}"
        echo "  Resources: $STATS"
        
        SCREENS=$(sudo docker exec "$CONTAINER" screen -list 2>/dev/null | grep -c "nexus-session" || ech
o "0")
        if [ "$SCREENS" -gt 0 ]; then
            echo -e "  Screens:   ${GREEN}$SCREENS active${NC}"
        else
            echo -e "  Screens:   ${RED}None${NC}"
        fi
        
        PROCS=$(sudo docker exec "$CONTAINER" ps aux | grep "nexus-network start" | grep -v grep | wc -l)
        if [ "$PROCS" -gt 0 ]; then
            echo -e "  Prover:    ${GREEN}Active ($PROCS)${NC}"
        else
            echo -e "  Prover:    ${YELLOW}Not running${NC}"
        fi
        
        LAST_LOG=$(sudo docker exec "$CONTAINER" tail -1 /root/logs/nexus.log 2>/dev/null | cut -c1-80)
        [ -n "$LAST_LOG" ] && echo "  Last log:  $LAST_LOG"
        
    else
        ((STOPPED++))
        echo -e "  Status:    ${RED}❌ Stopped${NC}"
    fi
    echo ""
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Total: ${GREEN}$RUNNING running${NC}, ${RED}$STOPPED stopped${NC}"
echo ""
echo -e "${CYAN}System Resources:${NC}"
echo "  CPU:  $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
echo "  RAM:  $(free -h | grep Mem | awk '{print $3 "/" $2}')"
echo ""
sudo docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
    $(sudo docker ps --filter "name=$CONTAINER_PREFIX-" --format "{{.Names}}")
