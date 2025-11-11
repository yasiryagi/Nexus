#!/bin/bash
CONTAINER_NUM=${1:-1}
sudo docker exec nexus-$CONTAINER_NUM tail -f /root/logs/nexus.log
