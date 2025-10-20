# Docker Deployment Automation Script

##  Project Overview

A robust, production-grade Bash script that automates the complete setup, deployment, and configuration of Dockerized applications on remote Linux servers. This script handles everything from repository cloning to Nginx reverse proxy configuration with comprehensive error handling and logging.

## 📋 Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Parameters](#parameters)
- [Script Workflow](#script-workflow)
- [Error Handling](#error-handling)
- [Logging](#logging)
- [Troubleshooting](#troubleshooting)
- [Examples](#examples)

## ✨ Features

- **Automated Repository Management**: Clone or pull latest changes from Git repositories
- **Docker Deployment**: Build and run containers using Dockerfile or docker-compose
- **Nginx Configuration**: Automatic reverse proxy setup for HTTP traffic
- **Comprehensive Validation**: Input validation, SSH connectivity checks, and deployment verification
- **Error Handling**: Trap functions for unexpected errors with meaningful exit codes
- **Logging**: Timestamped logs for all operations
- **Idempotency**: Safe to re-run without breaking existing setups
- **Cleanup**: Automatic cleanup of old containers and unused Docker resources

## 🔧 Prerequisites

### Local Machine Requirements:
- Bash shell (Linux/macOS/WSL/Termux)
- Git
- SSH client
- rsync or scp
- curl (for validation)

### Remote Server Requirements:
- Ubuntu/Debian-based Linux distribution
- SSH access with key-based authentication
- Sudo privileges
- Internet connection

### Required Information:
- Git repository URL (HTTPS)
- Personal Access Token (PAT) for private repositories
- SSH credentials (username, IP address, SSH key path)
- Application port number (internal container port)

## 📥 Installation

1. **Download the script:**
   ```bash
   wget https://your-repo-url/deploy.sh
   # OR
   curl -O https://your-repo-url/deploy.sh
   ```

2. **Make it executable:**
   ```bash
   chmod +x deploy.sh
   ```

3. **Ensure SSH key has correct permissions:**
   ```bash
   chmod 400 /path/to/your/ssh-key.pem
   ```

## 🚀 Usage

### Basic Usage

```bash
./deploy.sh
```

The script will interactively prompt you for all required parameters.

### Example Session

```bash
$ ./deploy.sh

================================================
  Docker Deployment Automation Script
================================================

[INFO] Collecting deployment parameters...
Enter Git Repository URL: https://github.com/username/repo.git
Enter Personal Access Token (PAT): ****
Enter branch name (default: main): main
Enter SSH username: ubuntu
Enter server IP address: 54.234.226.135
Enter SSH key path: ~/path/to/key.pem
Enter application port (internal container port): 3000
```

## 📝 Parameters

| Parameter | Description | Example | Required |
|-----------|-------------|---------|----------|
| **Git Repository URL** | HTTPS URL of your Git repository | `https://github.com/user/repo.git` | Yes |
| **Personal Access Token** | GitHub/GitLab PAT for authentication | `ghp_xxxxxxxxxxxx` | Yes |
| **Branch Name** | Git branch to deploy | `main` or `develop` | No (defaults to `main`) |
| **SSH Username** | Username for remote server | `ubuntu` or `ec2-user` | Yes |
| **Server IP Address** | IP address of remote server | `54.234.226.135` | Yes |
| **SSH Key Path** | Path to SSH private key | `~/.ssh/id_rsa` or `~/key.pem` | Yes |
| **Application Port** | Internal container port | `3000`, `8080`, `5000` | Yes |

## 🔄 Script Workflow

### Step 1: Parameter Collection
- Validates all user inputs
- Checks URL format, IP address, port range, and file existence
- Expands tilde (`~`) in file paths

### Step 2: Repository Cloning
- Authenticates using PAT
- Clones repository or pulls latest changes if already exists
- Switches to specified branch

### Step 3: Docker File Verification
- Checks for `Dockerfile` or `docker-compose.yml`
- Logs success or failure

### Step 4: SSH Connection Testing
- Tests SSH connectivity with provided credentials
- Performs ping test for network reachability
- Provides troubleshooting hints on failure

### Step 5: Remote Environment Preparation
- Updates system packages
- Installs Docker, Docker Compose, and Nginx (if missing)
- Adds user to Docker group
- Enables and starts services
- Unmasks Docker service if needed

### Step 6: File Transfer
- Creates remote project directory
- Transfers files using rsync (or scp as fallback)
- Preserves file permissions

### Step 7: Docker Deployment
- Stops and removes old containers
- Cleans up Docker resources
- Builds Docker image with lowercase name
- Runs container with port mapping
- Validates container health

### Step 8: Nginx Configuration
- Creates reverse proxy configuration
- Forwards HTTP (port 80) traffic to container
- Tests and reloads Nginx
- Removes default site configuration

### Step 9: Deployment Validation
- Verifies Docker service status
- Checks container health and logs
- Tests Nginx proxy functionality
- Tests local and remote connectivity

### Step 10: Cleanup
- Removes stopped containers
- Prunes unused images and networks
- Frees up disk space

## 🛡️ Error Handling

The script implements robust error handling:

- **`set -euo pipefail`**: Exits immediately on errors
- **Trap Functions**: Catches unexpected errors with line numbers
- **Input Validation**: Validates all user inputs before execution
- **Meaningful Exit Codes**: Different codes for different error types
- **Detailed Error Messages**: Clear messages with troubleshooting hints

### Common Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid input |
| 3 | SSH connection failed |
| 4 | File transfer failed |
| 5 | Docker deployment failed |

## 📊 Logging

All operations are logged to timestamped files:

- **Log File Format**: `deploy_YYYYMMDD_HHMMSS.log`
- **Log Levels**: INFO, SUCCESS, WARNING, ERROR
- **Content**: Commands executed, outputs, and timestamps

**View logs:**
```bash
cat deploy_20251020_181619.log
tail -f deploy_20251020_181619.log  # Follow in real-time
```

## 🔍 Troubleshooting

### SSH Connection Failed

**Symptoms**: `[ERROR] SSH connection failed`

**Solutions**:
1. Verify SSH key permissions: `chmod 400 /path/to/key.pem`
2. Check server is running and accessible
3. Verify security group allows SSH (port 22)
4. Test manually: `ssh -i /path/to/key.pem user@ip`

### Docker Image Name Error

**Symptoms**: `invalid reference format: repository name must be lowercase`

**Solution**: The script automatically converts names to lowercase. Ensure you're using the latest version.

### Permission Denied During File Transfer

**Symptoms**: `Permission denied` or `mkdir failed`

**Solutions**:
1. Ensure SSH user has write permissions
2. Try: `ssh user@ip "mkdir -p ~/target-directory"`
3. Check disk space: `df -h`

### Container Not Starting

**Symptoms**: Container exits immediately after starting

**Solutions**:
1. Check container logs: `docker logs container-name`
2. Verify Dockerfile is correct
3. Check port conflicts: `sudo netstat -tulpn | grep PORT`

### Nginx Configuration Error

**Symptoms**: `nginx: [emerg] could not build server_names_hash`

**Solutions**:
1. Test config: `sudo nginx -t`
2. Check syntax errors in config file
3. Restart Nginx: `sudo systemctl restart nginx`

### Application Not Accessible Externally

**Symptoms**: Works locally but not from outside

**Solutions**:
1. **AWS Security Group**: Allow HTTP (port 80) inbound rule
2. **Firewall**: Check UFW/iptables rules
3. **Test**: `curl http://SERVER_IP` from different network

## 💡 Examples

### Example 1: Deploy Node.js Application

```bash
./deploy.sh

# When prompted:
Repository URL: https://github.com/cliudcaptain9/scriots_automation.git
PAT: ghp_xxxxxxxxxxxx
Branch: main
Username: ubuntu
IP: 54.234.226.135
SSH Key: ~/.ssh/ec2-key.pem
Port: 3000
```

### Example 2: Deploy with Docker Compose

If your repository has `docker-compose.yml`, the script automatically detects and uses it:

```yaml
# docker-compose.yml
version: '3.8'
services:
  web:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
```

### Example 3: Re-deploy Updated Code

The script is idempotent - just run it again:

```bash
./deploy.sh
# It will pull latest changes and redeploy
```

## 🎯 Project Structure

```
.
├── deploy.sh                    # Main deployment script
├── deploy_YYYYMMDD_HHMMSS.log  # Timestamped log files
├── README.md                    # This file
└── Dockerfile                   # Your application Dockerfile
```

 Deployment Architecture

```
┌─────────────────┐
│  Local Machine  │
│   (Termux/PC)   │
└────────┬────────┘
         │ SSH
         ▼
┌─────────────────────────┐
│   Remote EC2 Server     │
│                         │
│  ┌──────────────────┐  │
│  │  Nginx (Port 80) │  │
│  └────────┬─────────┘  │
│           │             │
│           ▼             │
│  ┌──────────────────┐  │
│  │ Docker Container │  │
│  │   (Port 3000)    │  │
│  └──────────────────┘  │
└─────────────────────────┘
```

## 📈 Best Practices

1. **Always test SSH connection** before running script
2. **Use strong PATs** and never commit them to repositories
3. **Keep SSH keys secure** with proper permissions (400)
4. *Review logs* after deployment for any warnings
5. *Test locally first* before deploying to production
6. *Backup data* before redeployment
7. *Use version tags* in Git for production deployments
8. *Monitor container logs* after deployment

 Security Considerations

- SSH keys should have `400` permissions
- Never commit PATs or secrets to Git
- Use environment variables for sensitive data
- Regularly update Docker images and dependencies
- Configure firewall rules appropriately
- Use HTTPS/SSL certificates for production (add Let's Encrypt)

 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly
4. Submit a pull request

 License

This project is licensed under the MIT License.

 Author

Onyekachi

 Acknowledgments

- Inspired by DevOps automation best practices
- Built for cloud deployment scenarios
- Tested on AWS EC2 Ubuntu instances

 Support

For issues, questions, or contributions:
- Open an issue on GitHub
- Check troubleshooting section above
- Review log files for detailed error information

---

**Last Updated**: October 2025

**Version**: 1.0.0

**Tested On**: 
- Ubuntu 24.04 LTS
- Docker 28.2.2
- Nginx 1.24.0
