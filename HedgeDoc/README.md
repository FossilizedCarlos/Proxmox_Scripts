# HedgeDoc Proxmox Container Setup Script

A comprehensive script for deploying HedgeDoc (collaborative markdown editor) in a Proxmox LXC container with automatic Git backups, Docker, and production-ready configuration.

![](https://img.shields.io/badge/Builtwith-Ollama-Black?logo=ollama&logoColor=FFFFFF&label=Built%20with&color=1A1A1A) ![](https://img.shields.io/badge/Builtwith-Claude-orange?logo=claude&logoColor=FFFFFF&label=Built%20with&color=D97757)

## 🚀 Quick Start

```bash
wget https://raw.githubusercontent.com/yourusername/proxmox-scripts/main/hedgedoc-setup.sh
chmod +x hedgedoc-setup.sh
./hedgedoc-setup.sh
```

## ✨ Features

### Container Management
- **Interactive Setup Wizard**: Easy configuration through whiptail dialogs
- **Flexible Resource Allocation**: Choose CPU cores, memory, and disk size
- **Auto-login Option**: Configure root password or enable automatic console login
- **SSH Ready**: Root SSH access enabled for remote management

### HedgeDoc Deployment
- **Docker-based Installation**: Uses Docker Compose for easy management
- **PostgreSQL Database**: Dedicated database container with health checks
- **Automatic CSS/Asset Fix**: Properly configured domain settings prevent missing styles
- **URL-safe Password Generation**: Avoids special characters that break database connections
- **Smart Dependency Management**: HedgeDoc waits for database to be fully ready

### Git Backup System
- **Automatic Hourly Backups**: Cron job runs every hour, only commits changes
- **Metadata Preservation**: Keeps creation date, author, and update timestamps
- **Smart Commit Messages**: Shows number of changed files in each backup
- **Remote Repository Support**: Easy integration with GitHub, GitLab, or custom Git servers
- **Deleted Note Handling**: Automatically removes backups of deleted notes
- **Local-First Design**: Works without remote repository, push when ready

### Production Features
- **Systemd Service**: HedgeDoc runs as a system service with auto-restart
- **IPv6 Disabled**: Prevents connectivity issues in IPv4-only environments
- **Locale Configuration**: UTF-8 encoding properly set
- **Volume Persistence**: Database and uploads survive container updates
- **Health Monitoring**: Built-in health checks for all services

## 📋 What Gets Installed

### System Components
- Debian 12 (latest stable)
- Docker CE with Docker Compose plugin
- Git (for backup system)
- PostgreSQL 13 (Alpine-based, lightweight)
- HedgeDoc (latest version)

### Directory Structure
```
/opt/hedgedoc/
├── docker-compose.yml     # Main configuration
├── .env                   # Database passwords
├── git-backup.sh         # Automatic backup script
├── add-git-remote.sh     # Remote repository wizard
├── git-status.sh         # Backup status checker
├── git-backup/           # Local Git repository
│   └── *.md             # Backed up notes
└── git-backup.log       # Backup operation logs
```

## 🎯 Key Benefits

### 1. **Zero-Configuration Start**
- Works immediately after installation
- No manual configuration needed
- Automatic IP detection for proper URL setup

### 2. **Data Safety**
- Hourly automatic backups to Git
- Optional remote repository push
- Preserves all note metadata
- Easy restore from markdown files

### 3. **Production Ready**
- Proper health checks prevent startup race conditions
- Systemd integration for reliability
- Automatic restart on failures
- Resource limits prevent system overload

### 4. **Maintenance Friendly**
- All configuration in one place (`/opt/hedgedoc/`)
- Simple systemctl commands for management
- Clear logging for troubleshooting
- Easy updates via Docker Compose

### 5. **Security Conscious**
- URL-safe password generation
- No hardcoded credentials
- Optional authentication methods
- Private notes by default

## 🔧 Post-Installation Management

### Service Control
```bash
systemctl status hedgedoc    # Check status
systemctl restart hedgedoc   # Restart services
systemctl stop hedgedoc      # Stop services
```

### View Logs
```bash
cd /opt/hedgedoc
docker compose logs -f      # Follow all logs
docker compose logs hedgedoc # HedgeDoc logs only
tail -f git-backup.log      # Backup logs
```

### Git Backup Management

**Add Remote Repository** (anytime):
```bash
/opt/hedgedoc/add-git-remote.sh
```

**Check Backup Status**:
```bash
/opt/hedgedoc/git-status.sh
```

**Manual Backup**:
```bash
/opt/hedgedoc/git-backup.sh
```

### Update HedgeDoc
```bash
cd /opt/hedgedoc
docker compose pull
docker compose up -d
```

## 🔐 Security Notes

1. **Change Session Secret**: Edit `CMD_SESSION_SECRET` in docker-compose.yml
2. **Configure Authentication**: Add OAuth providers (GitHub, Google, etc.)
3. **Enable HTTPS**: Set `CMD_PROTOCOL_USESSL=true` when using reverse proxy
4. **Restrict Registration**: Set `CMD_ALLOW_EMAIL_REGISTER=false` if needed

## 🐛 Troubleshooting

### CSS/Assets Not Loading
- Clear browser cache (Ctrl+F5)
- Check `CMD_DOMAIN` matches your access IP
- Verify port 3000 is accessible

### Database Connection Issues
- Check if database container is healthy: `docker ps`
- Verify password in docker-compose.yml has no special characters
- Check logs: `docker compose logs database`

### Git Backup Issues
- Verify cron is running: `systemctl status cron`
- Check backup logs: `/opt/hedgedoc/git-backup.log`
- Test manually: `/opt/hedgedoc/git-backup.sh`

## 📦 Backup & Restore

### Backup Everything
```bash
# Database
docker exec hedgedoc-database-1 pg_dump -U hedgedoc hedgedoc > hedgedoc_backup.sql

# Uploads
docker run --rm -v hedgedoc_uploads:/data -v $(pwd):/backup alpine tar czf /backup/uploads_backup.tar.gz -C /data .

# Git repository
tar czf git-backup.tar.gz /opt/hedgedoc/git-backup/
```

### Restore from Backup
```bash
# Database
docker exec -i hedgedoc-database-1 psql -U hedgedoc hedgedoc < hedgedoc_backup.sql

# Uploads
docker run --rm -v hedgedoc_uploads:/data -v $(pwd):/backup alpine tar xzf /backup/uploads_backup.tar.gz -C /data

# Restart services
systemctl restart hedgedoc
```

## 🚀 Advanced Configuration

### Add OAuth Authentication
Edit `/opt/hedgedoc/docker-compose.yml` and add:
```yaml
- CMD_OAUTH2_CLIENT_ID=your_client_id
- CMD_OAUTH2_CLIENT_SECRET=your_client_secret
```

### Change Database Password
1. Generate new password: `openssl rand -base64 32 | tr -d "=+/" | cut -c1-25`
2. Update in docker-compose.yml
3. Restart: `docker compose down && docker compose up -d`

### Enable Anonymous Access
```yaml
- CMD_ALLOW_ANONYMOUS=true
- CMD_ALLOW_ANONYMOUS_EDITS=true
```

## 📄 License

This script is provided as-is for deploying HedgeDoc in Proxmox environments. HedgeDoc itself is licensed under AGPL-3.0.

## 🤝 Contributing

Improvements welcome! Key areas:
- Additional backup destinations (S3, WebDAV)
- Automated SSL setup with Let's Encrypt
- Multi-node deployment support
- Monitoring integration

---

**Note**: This script creates a production-ready HedgeDoc instance with automatic backups. Always test in a non-production environment first and adjust resources based on your needs.
