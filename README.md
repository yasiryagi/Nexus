# Nexus
Docker deployment for nexus testnet 
docker build -t nexus-setup .
docker run -it -d --name nexus11 -e NODE_ID=<your_node_id> nexus-setup
