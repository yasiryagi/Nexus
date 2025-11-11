#!/bin/bash
./stop-containers.sh
echo ""
sleep 3
if [[ -f .env ]]; then
    source .env
    ./create-containers.sh
else
    echo "Provide NODE_IDS: ./create-containers.sh <ids>"
fi
