#!/bin/bash

# === Prompt for container settings ===
VMID=$(whiptail --inputbox "Enter VMID for the container:" 8 60 200 --title "Container Setup" 3>&1 1>&2 2>&3)
HOSTNAME=$(whiptail --inputbox "Enter hostname for the container:" 8 60 hedgedoc --title "Container Setup" 3>&1 1>&2 2>&3)
CORES=$(whiptail --inputbox "Enter number of CPU cores:" 8 60 2 --title "Container Setup" 3>&1 1>&2 2>&3)
CPULIMIT=$(whiptail --inputbox "Enter CPU limit (e.g., 1 = 100%, 0.5 = 50%):" 8 60 1 --title "Container Setup" 3>&1 1>&2 2>&3)
MEMORY=$(whiptail --inputbox "Enter memory in MB (e.g., 4096):" 8 60 4096 --title "Container Setup" 3>&1 1>&2 2>&3)
SWAP=$(whiptail --inputbox "Enter swap in MB (e.g., 1024):" 8 60 1024 --title "Container Setup" 3>&1 1>&2 2>&3)
ROOTFS=$(whiptail --inputbox "Enter root disk size (in GB, numbers only):" 8 60 64 --title "Container Setup" 3>&1 1>&2 2>&3)
ROOT_PASSWORD=$(whiptail --passwordbox "Enter root password (leave blank for auto-login):" 8 60 --title "Container Setup" 3>&1 1>&2 2>&3)

# === Static/default values ===
OSTEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
STORAGE="local-lvm"
BRIDGE="vmbr0"
TAGS="hedgedoc,docker"

# === Create the container ===
pct create "$VMID" "$OSTEMPLATE" \
    --hostname "$HOSTNAME" \
    --storage "$STORAGE" \
    --rootfs "$ROOTFS" \
    --memory "$MEMORY" \
    --swap "$SWAP" \
    --net0 name=eth0,bridge="$BRIDGE",ip=dhcp,ip6=manual \
    --cores "$CORES" \
    --cpulimit "$CPULIMIT" \
    --features keyctl=1,nesting=1 \
    --tag "$TAGS"

# === Start the container ===
pct start "$VMID"
sleep 2

# === Set root password or enable auto-login ===
if [ -n "$ROOT_PASSWORD" ]; then
    pct exec "$VMID" -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"
    echo -e "\e[32mRoot password set.\e[0m"
else
    echo -e "\e[34mEnabling root autologin...\e[0m"

    # Create override directory
    pct exec "$VMID" -- mkdir -p /etc/systemd/system/getty@tty1.service.d

    # Write override configuration
    pct exec "$VMID" -- bash -c "cat << 'EOF' > /etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF"

    # Reload systemd and restart the getty service
    pct exec "$VMID" -- systemctl daemon-reload
    pct exec "$VMID" -- systemctl restart getty@tty1

    echo -e "\e[32mRoot autologin enabled on tty1.\e[0m"
fi

# === Enable SSH root login ===
pct exec "$VMID" -- bash -c "sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && systemctl restart ssh"

# === Update and upgrade system ===
pct exec "$VMID" -- apt update
pct exec "$VMID" -- apt upgrade -y
echo -e "\e[32mSystem updated and upgraded!\e[0m"

# === Set locale ===
pct exec "$VMID" -- bash -c "echo 'export LANG=en_US.UTF-8' >> /etc/profile"
pct exec "$VMID" -- bash -c "echo 'export LC_ALL=en_US.UTF-8' >> /etc/profile"
pct exec "$VMID" -- bash -c "source /etc/profile"
echo -e "\e[32mLocale set to en_US.UTF-8.\e[0m"

# === Disable IPv6 ===
pct exec "$VMID" -- sh -c 'echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf'
pct exec "$VMID" -- sh -c 'echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf'
pct exec "$VMID" -- sh -c 'echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf'
pct exec "$VMID" -- sh -c 'echo "net.ipv6.conf.eth0.disable_ipv6 = 1" >> /etc/sysctl.conf && sysctl -p'
echo -e "\e[32mIPv6 Deactivated!\e[0m"

# === Install Docker and tools ===
echo -e "\e[34mInstalling Docker and tools...\e[0m"

# Install Docker and tools
pct exec "$VMID" -- bash -c "apt-get install -y ca-certificates curl"
pct exec "$VMID" -- bash -c "install -m 0755 -d /etc/apt/keyrings"
pct exec "$VMID" -- bash -c "curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc"
pct exec "$VMID" -- bash -c "chmod a+r /etc/apt/keyrings/docker.asc"
pct exec "$VMID" -- bash -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null'
pct exec "$VMID" -- bash -c "apt-get update"
pct exec "$VMID" -- bash -c "apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
printf "\e[32mInstalled Docker and tools\e[0m\n"

# === Install HedgeDoc using Docker Compose ===
echo -e "\e[34mInstalling HedgeDoc...\e[0m"

# Create HedgeDoc directory
pct exec "$VMID" -- mkdir -p /opt/hedgedoc

# Get container IP address
CONTAINER_IP=$(pct exec "$VMID" -- hostname -I | awk '{print $1}')

# Generate random passwords for database (URL-safe)
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
HEDGEDOC_SESSION_SECRET=$(openssl rand -hex 32)

# Create docker-compose.yml
pct exec "$VMID" -- bash -c "cat << 'EOF' > /opt/hedgedoc/docker-compose.yml
services:
  database:
    image: postgres:13-alpine
    restart: always
    environment:
      - POSTGRES_USER=hedgedoc
      - POSTGRES_PASSWORD=$DB_PASSWORD
      - POSTGRES_DB=hedgedoc
    volumes:
      - database:/var/lib/postgresql/data
    networks:
      - hedgedoc
    healthcheck:
      test: [\"CMD-SHELL\", \"pg_isready -U hedgedoc\"]
      interval: 5s
      timeout: 5s
      retries: 5

  hedgedoc:
    image: quay.io/hedgedoc/hedgedoc:latest
    restart: always
    depends_on:
      database:
        condition: service_healthy
    environment:
      - CMD_DB_URL=postgres://hedgedoc:$DB_PASSWORD@database:5432/hedgedoc
      - CMD_DOMAIN=$CONTAINER_IP
      - CMD_PORT=3000
      - CMD_PROTOCOL_USESSL=false
      - CMD_URL_ADDPORT=true
      - CMD_ALLOW_ANONYMOUS=false
      - CMD_ALLOW_ANONYMOUS_EDITS=false
      - CMD_ALLOW_EMAIL_REGISTER=true
      - CMD_SESSION_SECRET=$HEDGEDOC_SESSION_SECRET
      - CMD_ALLOW_GRAVATAR=true
      - CMD_DEFAULT_PERMISSION=private
      - CMD_IMAGE_UPLOAD_TYPE=filesystem
    ports:
      - \"3000:3000\"
    volumes:
      - uploads:/hedgedoc/public/uploads
    networks:
      - hedgedoc

volumes:
  database:
  uploads:

networks:
  hedgedoc:
    driver: bridge
EOF"

# Create .env file with configuration
pct exec "$VMID" -- bash -c "cat << EOF > /opt/hedgedoc/.env
# Database configuration
POSTGRES_PASSWORD=$DB_PASSWORD
HEDGEDOC_SESSION_SECRET=$HEDGEDOC_SESSION_SECRET

# HedgeDoc configuration
# Update CMD_DOMAIN with your actual domain or IP address
# Set CMD_PROTOCOL_USESSL=true if using HTTPS
# Container IP: $CONTAINER_IP
EOF"

# Create systemd service for HedgeDoc
pct exec "$VMID" -- bash -c "cat << 'EOF' > /etc/systemd/system/hedgedoc.service
[Unit]
Description=HedgeDoc
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/hedgedoc
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose pull && /usr/bin/docker compose up -d

[Install]
WantedBy=multi-user.target
EOF"

# Enable and start HedgeDoc service
pct exec "$VMID" -- systemctl daemon-reload
pct exec "$VMID" -- systemctl enable hedgedoc.service
pct exec "$VMID" -- systemctl start hedgedoc.service

# Wait for services to start
echo -e "\e[34mWaiting for HedgeDoc to start...\e[0m"
sleep 30

# Check if services are running
pct exec "$VMID" -- docker compose -f /opt/hedgedoc/docker-compose.yml ps

# === Set up Git Backup ===
echo -e "\e[34mSetting up Git backup system...\e[0m"

# Create git backup script
pct exec "$VMID" -- bash -c 'cat << '\''EOF'\'' > /opt/hedgedoc/git-backup.sh
#!/bin/bash
BACKUP_DIR="/opt/hedgedoc/git-backup"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
CONFIG_FILE="/opt/hedgedoc/.git-backup-config"

# Load config if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Initialize git repo if not exists
if [ ! -d "$BACKUP_DIR/.git" ]; then
    mkdir -p $BACKUP_DIR
    cd $BACKUP_DIR
    git init --initial-branch=main
    git config user.name "HedgeDoc Backup"
    git config user.email "backup@hedgedoc.local"
    
    # Create README
    cat << '\''README'\'' > README.md
# HedgeDoc Backup Repository

This repository contains automatic backups of HedgeDoc notes.

## Structure
- Each note is saved as a markdown file
- Filename format: `[shortid]_[title].md`
- Metadata is preserved in frontmatter

## Restore
To restore a note, copy its content back to HedgeDoc.

## Remote Repository
To add a remote repository later, run:
```
/opt/hedgedoc/add-git-remote.sh
```
README
    git add README.md
    git commit -m "Initial commit"
fi

cd $BACKUP_DIR

# Export all notes with metadata
docker exec hedgedoc-database-1 psql -U hedgedoc hedgedoc -c "
SELECT 
    n.shortid,
    COALESCE(n.title, '\''Untitled'\'') as title,
    n.content,
    n.createdAt,
    n.updatedAt,
    COALESCE(u.email, '\''anonymous'\'') as author
FROM notes n
LEFT JOIN users u ON n.ownerId = u.id
WHERE n.deletedAt IS NULL
ORDER BY n.updatedAt DESC
" -t -A -F"|||" 2>/dev/null | while IFS='\''|||'\'' read -r shortid title content created updated author; do
    # Sanitize filename
    safe_title=$(echo "$title" | sed '\''s/[^a-zA-Z0-9-]/_/g'\'' | cut -c1-50)
    filename="${shortid}_${safe_title}.md"
    
    # Add frontmatter and content
    cat << NOTE > "$filename"
---
id: $shortid
title: "$title"
created: $created
updated: $updated
author: $author
---

$content
NOTE
done

# Check if there are changes
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    # Changes detected, commit them
    git add -A
    
    # Create meaningful commit message
    CHANGES=$(git diff --cached --numstat 2>/dev/null | wc -l)
    git commit -m "Backup $DATE - $CHANGES files changed"
    
    echo "$(date): ✓ Backup completed: $CHANGES files changed" >> /opt/hedgedoc/git-backup.log
    
    # Push to remote if configured
    if git remote 2>/dev/null | grep -q origin; then
        if git push origin main 2>/dev/null; then
            echo "$(date): ✓ Pushed to remote repository" >> /opt/hedgedoc/git-backup.log
        else
            echo "$(date): ⚠ Failed to push to remote" >> /opt/hedgedoc/git-backup.log
        fi
    fi
else
    echo "$(date): → No changes detected, skipping backup" >> /opt/hedgedoc/git-backup.log
fi

# Clean up old markdown files that no longer exist in database
for file in *.md; do
    if [ "$file" != "README.md" ] && [ -f "$file" ]; then
        shortid=$(echo "$file" | cut -d'\''_'\'' -f1)
        EXISTS=$(docker exec hedgedoc-database-1 psql -U hedgedoc hedgedoc -t -c "SELECT 1 FROM notes WHERE shortid='\''$shortid'\'' AND deletedAt IS NULL" 2>/dev/null)
        if [ -z "$EXISTS" ]; then
            git rm "$file" 2>/dev/null
            echo "$(date): → Removed deleted note: $file" >> /opt/hedgedoc/git-backup.log
        fi
    fi
done

# Commit deletions if any
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    git commit -m "Removed deleted notes - $DATE"
fi
EOF'

pct exec "$VMID" -- chmod +x /opt/hedgedoc/git-backup.sh

# Create script to add remote repository later
pct exec "$VMID" -- bash -c 'cat << '\''EOF'\'' > /opt/hedgedoc/add-git-remote.sh
#!/bin/bash
BACKUP_DIR="/opt/hedgedoc/git-backup"
CONFIG_FILE="/opt/hedgedoc/.git-backup-config"

echo "=== HedgeDoc Git Backup Remote Configuration ==="
echo
echo "This script will help you add a remote Git repository for backups."
echo
echo "Supported options:"
echo "1. GitHub (using personal access token)"
echo "2. GitLab (using personal access token)"
echo "3. Custom Git server (SSH)"
echo "4. Custom Git server (HTTPS)"
echo
read -p "Choose option (1-4): " OPTION

case $OPTION in
    1)
        echo
        echo "GitHub Setup:"
        echo "1. Go to https://github.com/settings/tokens"
        echo "2. Generate a new token with '\''repo'\'' scope"
        echo "3. Create a new repository on GitHub for backups"
        echo
        read -p "Enter your GitHub username: " GH_USER
        read -p "Enter your repository name: " GH_REPO
        read -s -p "Enter your personal access token: " GH_TOKEN
        echo
        
        cd $BACKUP_DIR
        git remote remove origin 2>/dev/null
        git remote add origin https://${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git
        
        # Save config
        echo "REMOTE_TYPE=github" > $CONFIG_FILE
        echo "REMOTE_USER=$GH_USER" >> $CONFIG_FILE
        echo "REMOTE_REPO=$GH_REPO" >> $CONFIG_FILE
        ;;
        
    2)
        echo
        echo "GitLab Setup:"
        read -p "Enter GitLab domain (or press Enter for gitlab.com): " GL_DOMAIN
        GL_DOMAIN=${GL_DOMAIN:-gitlab.com}
        read -p "Enter your GitLab username: " GL_USER
        read -p "Enter your repository name: " GL_REPO
        read -s -p "Enter your personal access token: " GL_TOKEN
        echo
        
        cd $BACKUP_DIR
        git remote remove origin 2>/dev/null
        git remote add origin https://${GL_USER}:${GL_TOKEN}@${GL_DOMAIN}/${GL_USER}/${GL_REPO}.git
        
        # Save config
        echo "REMOTE_TYPE=gitlab" > $CONFIG_FILE
        echo "REMOTE_DOMAIN=$GL_DOMAIN" >> $CONFIG_FILE
        echo "REMOTE_USER=$GL_USER" >> $CONFIG_FILE
        echo "REMOTE_REPO=$GL_REPO" >> $CONFIG_FILE
        ;;
        
    3)
        echo
        echo "SSH Setup:"
        read -p "Enter Git SSH URL (e.g., git@server.com:user/repo.git): " SSH_URL
        
        cd $BACKUP_DIR
        git remote remove origin 2>/dev/null
        git remote add origin $SSH_URL
        
        echo "REMOTE_TYPE=ssh" > $CONFIG_FILE
        echo "REMOTE_URL=$SSH_URL" >> $CONFIG_FILE
        
        echo
        echo "Note: Make sure to set up SSH keys in /root/.ssh/"
        ;;
        
    4)
        echo
        echo "HTTPS Setup:"
        read -p "Enter Git HTTPS URL: " HTTPS_URL
        read -p "Enter username: " HTTPS_USER
        read -s -p "Enter password/token: " HTTPS_PASS
        echo
        
        cd $BACKUP_DIR
        git remote remove origin 2>/dev/null
        # URL encode the password
        ENCODED_PASS=$(echo -n "$HTTPS_PASS" | jq -sRr @uri)
        REMOTE_URL=$(echo $HTTPS_URL | sed "s|https://|https://${HTTPS_USER}:${ENCODED_PASS}@|")
        git remote add origin $REMOTE_URL
        
        echo "REMOTE_TYPE=https" > $CONFIG_FILE
        ;;
esac

echo
echo "Testing connection..."
cd $BACKUP_DIR

# Try to push
if git push -u origin main 2>&1; then
    echo "✓ Successfully connected to remote repository!"
    echo "✓ Automatic backups will now push to remote"
    
    # Run an immediate backup
    /opt/hedgedoc/git-backup.sh
else
    echo "✗ Failed to connect to remote repository"
    echo "Please check your credentials and try again"
    git remote remove origin 2>/dev/null
    rm -f $CONFIG_FILE
fi
EOF'

pct exec "$VMID" -- chmod +x /opt/hedgedoc/add-git-remote.sh

# Create git status check script
pct exec "$VMID" -- bash -c 'cat << '\''EOF'\'' > /opt/hedgedoc/git-status.sh
#!/bin/bash
BACKUP_DIR="/opt/hedgedoc/git-backup"

echo "=== HedgeDoc Git Backup Status ==="
echo

if [ -d "$BACKUP_DIR/.git" ]; then
    cd $BACKUP_DIR
    
    # Check remote
    if git remote | grep -q origin; then
        REMOTE_URL=$(git remote get-url origin 2>/dev/null | sed '\''s|https://[^@]*@|https://|'\'')
        echo "Remote repository: $REMOTE_URL"
        
        # Check connection
        if git ls-remote --heads origin main &>/dev/null; then
            echo "Remote status: ✓ Connected"
        else
            echo "Remote status: ✗ Not accessible"
        fi
    else
        echo "Remote repository: Not configured"
        echo "Run /opt/hedgedoc/add-git-remote.sh to add one"
    fi
    
    echo
    echo "Local backup status:"
    echo "- Total notes backed up: $(ls -1 *.md 2>/dev/null | grep -v README.md | wc -l)"
    echo "- Last backup: $(git log -1 --format=%cd --date=relative 2>/dev/null || echo "Never")"
    echo "- Repository size: $(du -sh $BACKUP_DIR | cut -f1)"
    
    # Check if cron is set up
    echo
    if crontab -l 2>/dev/null | grep -q git-backup.sh; then
        echo "Automatic backup: ✓ Enabled"
        crontab -l | grep git-backup.sh
    else
        echo "Automatic backup: ✗ Not scheduled"
    fi
else
    echo "Git backup not initialized yet. Will be created on first backup."
fi

echo
echo "Recent backup log:"
tail -n 10 /opt/hedgedoc/git-backup.log 2>/dev/null || echo "No backup logs yet"
EOF'

pct exec "$VMID" -- chmod +x /opt/hedgedoc/git-status.sh

# Run initial backup to create repository
pct exec "$VMID" -- /opt/hedgedoc/git-backup.sh

# Set up cron job for hourly backups
pct exec "$VMID" -- bash -c '(crontab -l 2>/dev/null | grep -v "git-backup.sh"; echo "0 * * * * /opt/hedgedoc/git-backup.sh >> /opt/hedgedoc/git-backup.log 2>&1") | crontab -'

echo -e "\e[32mGit backup system configured!\e[0m"

# === Final message ===
echo -e "\e[32m================================================\e[0m"
echo -e "\e[32mContainer $VMID created and configured!\e[0m"
echo -e "\e[32m================================================\e[0m"
echo -e "\e[33mHedgeDoc is now running!\e[0m"
echo -e "\e[33mAccess HedgeDoc at: http://$CONTAINER_IP:3000\e[0m"
echo -e "\e[33m\e[0m"
echo -e "\e[33mIMPORTANT: Configuration files are in /opt/hedgedoc/\e[0m"
echo -e "\e[33m- Edit docker-compose.yml to change settings\e[0m"
echo -e "\e[33m- Database password saved in .env file\e[0m"
echo -e "\e[33m- To update domain: change CMD_DOMAIN in docker-compose.yml\e[0m"
echo -e "\e[33m\e[0m"
echo -e "\e[33mGit Backup System:\e[0m"
echo -e "\e[33m- Automatic hourly backups to: /opt/hedgedoc/git-backup/\e[0m"
echo -e "\e[33m- Add remote repository: /opt/hedgedoc/add-git-remote.sh\e[0m"
echo -e "\e[33m- Check backup status: /opt/hedgedoc/git-status.sh\e[0m"
echo -e "\e[33m- Backup logs: /opt/hedgedoc/git-backup.log\e[0m"
echo -e "\e[33m\e[0m"
echo -e "\e[33mTo manage HedgeDoc:\e[0m"
echo -e "\e[33m- systemctl start/stop/restart hedgedoc\e[0m"
echo -e "\e[33m- cd /opt/hedgedoc && docker compose logs\e[0m"
echo -e "\e[33m\e[0m"
echo -e "\e[33mDefault login: Sign up with email or configure OAuth\e[0m"
echo -e "\e[32m================================================\e[0m"
