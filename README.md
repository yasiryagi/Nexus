# Nexus Docker Container Management

Automated setup and monitoring for multiple Nexus prover containers.

## 🚀 Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/yasiryagi/Nexus.git
cd Nexus
```

### 2. Get Your Node IDs
1. Visit [https://app.nexus.xyz/nodes](https://app.nexus.xyz/nodes)
2. Log in to your Nexus account
3. Copy your node IDs from the dashboard

### 3. Setup Configuration
```bash
# Copy the example configuration
cp .env.example .env

# Edit with your node IDs
nano .env
```

Edit `.env` to include your node IDs:
```
NODE_IDS=7306098,7324770,6766348,6736075,6676501
```

### 4. Create Containers
```bash
chmod +x create_containers.sh
./create_containers.sh
```

### 5. Setup Monitoring (Optional)
```bash
# Setup cron job to check every 30 minutes
chmod +x monitor_script.sh
echo "*/30 * * * * $(pwd)/monitor_script.sh" | crontab -
```

## 📁 Files

- **`Dockerfile`** - Docker image with Nexus installed
- **`create_containers.sh`** - Creates and starts all containers
- **`monitor_script.sh`** - Monitors and fixes container issues
- **`.env`** - Your node IDs configuration
- **`README.md`** - This file

## 🔧 Container Management

### Check Status
```bash
# Manual check and fix
./monitor_script.sh

# View specific container logs
sudo docker exec nexus-1 tail -f /root/logs/nexus.log

# Connect to container
sudo docker exec -it nexus-1 screen -r nexus-session
```

### Useful Commands
```bash
# View all containers
sudo docker ps --filter "name=nexus-"

# View monitoring logs
tail -f /var/log/nexus_monitor.log

# Restart specific container
sudo docker restart nexus-1

# Stop all containers
sudo docker stop $(sudo docker ps -q --filter "name=nexus-")
```

## 🏗️ How It Works

### Container Creation
1. **Builds Docker image** with Nexus pre-installed
2. **Creates containers** for each node ID in `.env`
3. **Starts screen sessions** running Nexus prover
4. **Mounts persistent storage** for Nexus data and logs

### Monitoring
- **Checks container status** - Starts stopped containers
- **Checks screen sessions** - Creates missing sessions
- **Monitors Nexus processes** - Reports health status
- **Logs all actions** to `/var/log/nexus_monitor.log`

### File Structure
```
/home/nexus-containers/
├── nexus-data-1/     # Nexus data for container 1
├── nexus-data-2/     # Nexus data for container 2
├── logs-1/           # Logs for container 1
├── logs-2/           # Logs for container 2
└── ...
```

## 🔄 Adding/Removing Nodes

### Add New Nodes
1. Update `.env` file with new node IDs
2. Run `./create_containers.sh` (only creates missing containers)

### Remove Nodes
1. Update `.env` file (remove node IDs)
2. Manually stop and remove unwanted containers:
```bash
sudo docker stop nexus-X
sudo docker rm nexus-X
sudo rm -rf /home/nexus-containers/nexus-data-X
sudo rm -rf /home/nexus-containers/logs-X
```

## 🐛 Troubleshooting

### Container Won't Start
```bash
# Check Docker logs
sudo docker logs nexus-1

# Check if image exists
sudo docker images | grep nexus-node

# Rebuild if needed
./create_containers.sh --force-rebuild
```

### Nexus Not Running
```bash
# Check container status
./monitor_script.sh

# Check Nexus logs
sudo docker exec nexus-1 cat /root/logs/nexus.log

# Check startup logs
sudo docker exec nexus-1 cat /root/logs/startup.log
```

### Screen Session Issues
```bash
# List screen sessions
sudo docker exec nexus-1 screen -list

# Connect to screen
sudo docker exec -it nexus-1 screen -r nexus-session

# Kill and restart screen
sudo docker exec nexus-1 screen -S nexus-session -X quit
sudo docker exec -d nexus-1 screen -dmS nexus-session /root/start_nexus.sh
```

## 📊 Monitoring

### Cron Job Setup
The monitoring script can run automatically via cron:

```bash
# Every 30 minutes (recommended)
*/30 * * * * /path/to/monitor_script.sh

# Every 5 minutes (more responsive)
*/5 * * * * /path/to/monitor_script.sh

# View current cron jobs
crontab -l
```

### Log Files
- **Container logs**: `/home/nexus-containers/logs-X/nexus.log`
- **Restart logs**: `/home/nexus-containers/logs-X/restart.log`
- **Monitor logs**: `/var/log/nexus_monitor.log`

## 🔒 Security Notes

- Containers run with restart policies for reliability
- Data is persisted outside containers
- Logs are rotated to prevent disk space issues
- Monitor script only fixes detected issues

## 📞 Support

For issues:
1. Check the troubleshooting section
2. View logs for error details
3. Ensure your node IDs are correct at [https://app.nexus.xyz/nodes](https://app.nexus.xyz/nodes)

## 📝 License

This project is for managing Nexus prover containers. Follow Nexus terms of service.
