
## 🚀 Installation

It takes less than a minute to deploy the complete amokhan tech Manager on your fresh VPS. Choose the installation method that works best for you:



### MANAGER INSTALLATION💡
```bash

# on the server🚦

sudo rm -f /etc/resolv.conf && \
sudo tee /etc/resolv.conf >/dev/null <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
apt update && \
apt install -y curl && \
curl -L -o install.sh "https://raw.githubusercontent.com/noten28/manage/main/install.sh" && chmod +x install.sh && sudo ./install.sh && rm install.sh
```

### TO REINSTALL YOUR VPS OS 😊

```bash

# on the server🚦

sudo rm -f /etc/resolv.conf && \
sudo tee /etc/resolv.conf >/dev/null <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
apt update && \
apt install -y curl && \
curl -L -o reinstall.sh "https://raw.githubusercontent.com/noten28/manage/main/reinstall.sh" && chmod +x reinstall.sh && sudo ./reinstall.sh && rm reinstall.sh
```

<div align="center">
  <b>Built by Amokhan tech  FOUNDER~.Cyber 👨‍💻</b><br>
  <i>"Fast configuration, Secure tunneling, Beautiful interfaces."</i>
</div>
