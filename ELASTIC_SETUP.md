# Elastic Security — Setup Guide for Haki Demo VM

**VM:** Linux Mint 22.3 "Zena" | kernel 6.17.0-22-generic  
**Goal:** Install Elasticsearch + Kibana + Elastic Agent, enable kernel module monitoring,  
then prove the stack misses Diamorphine while `detector.py` catches it.

---

## 0. Before you start — snapshot the VM

```bash
# In VMware: VM → Snapshot → Take Snapshot
# Name it: "pre-elastic-install"
# You want a clean rollback point before you add ~2 GB of services.
```

---

## 1. System prerequisites

```bash
sudo apt update && sudo apt install -y curl gnupg apt-transport-https
```

Check that Java is **not** required — Elastic 8.x ships a bundled JDK. No manual Java install needed.

---

## 2. Add the Elastic APT repository

```bash
# Import the Elastic GPG key
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch \
  | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

# Add the 8.x repo
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update
```

> **Note:** The older `apt-key add` method shown in many guides is deprecated on Ubuntu 22+ / Mint 22. Use the `gpg --dearmor` method above to avoid warnings.

---

## 3. Install Elasticsearch

```bash
sudo apt install -y elasticsearch
```

### 3a. Configure for single-node demo use

Edit `/etc/elasticsearch/elasticsearch.yml`:

```bash
sudo nano /etc/elasticsearch/elasticsearch.yml
```

Add / uncomment these lines:

```yaml
cluster.name: haki-demo
node.name: haki-node-1
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node
xpack.security.enabled: true
xpack.security.http.ssl.enabled: false   # disable TLS for local demo simplicity
```

### 3b. Memory — IMPORTANT for your 7.7 GB VM

By default Elasticsearch claims up to 50 % of RAM. With 7.7 GB total you need to cap it.

Edit `/etc/elasticsearch/jvm.options.d/heap.options` (create the file):

```bash
sudo tee /etc/elasticsearch/jvm.options.d/heap.options <<'EOF'
-Xms1g
-Xmx1g
EOF
```

This leaves ample RAM for Kibana, the kernel, and your demo terminals.

### 3c. Start and enable

```bash
sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch
```

### 3d. Set the elastic superuser password

On first start, Elasticsearch 8.x auto-generates passwords. Reset it to something you'll remember for the demo:

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i
# Enter a password you'll remember, e.g.:  HakiDemo2025!
```

### 3e. Verify

```bash
curl -u elastic:HakiDemo2025! http://localhost:9200
# Expect: {"name":"haki-node-1","cluster_name":"haki-demo", ...}
```

---

## 4. Install Kibana

```bash
sudo apt install -y kibana
```

### 4a. Configure

Edit `/etc/kibana/kibana.yml`:

```bash
sudo nano /etc/kibana/kibana.yml
```

```yaml
server.port: 5601
server.host: "0.0.0.0"          # allows access from your Windows host browser
server.name: "haki-kibana"
elasticsearch.hosts: ["http://localhost:9200"]
elasticsearch.username: "kibana_system"
```

Set the `kibana_system` password:

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -i
# Use a simple password, e.g.:  kibana2025
```

Then add it to Kibana config:

```yaml
elasticsearch.password: "kibana2025"
```

### 4b. Start and enable

```bash
sudo systemctl enable kibana
sudo systemctl start kibana
```

### 4c. Verify from Windows host browser

```
http://<VM_IP>:5601
```

Get the VM IP:
```bash
hostname -I | awk '{print $1}'
```

Login: `elastic` / `HakiDemo2025!`

---

## 5. Install Elastic Agent (with Security integration)

Elastic Agent replaces the legacy Beats stack and includes Elastic Defend (EDR).

### 5a. Download and install

```bash
# Get the agent matching your stack version
ELASTIC_VERSION=$(curl -s http://localhost:9200 -u elastic:HakiDemo2025! \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['version']['number'])")

echo "Installing Elastic Agent $ELASTIC_VERSION"

curl -L -O "https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${ELASTIC_VERSION}-linux-x86_64.tar.gz"
tar xzf "elastic-agent-${ELASTIC_VERSION}-linux-x86_64.tar.gz"
cd "elastic-agent-${ELASTIC_VERSION}-linux-x86_64"
```

### 5b. Enroll with Fleet

In Kibana: **Management → Fleet → Add agent**

1. Select **Linux Tar** platform
2. Copy the enroll command — it will look like:

```bash
sudo ./elastic-agent install \
  --fleet-server-es=http://localhost:9200 \
  --fleet-server-service-token=<token> \
  --fleet-server-policy=fleet-server-policy \
  --fleet-server-es-ca-trusted-fingerprint=<fingerprint>
```

Run it. Agent installs as a systemd service.

### 5c. Verify agent is enrolled

```bash
sudo elastic-agent status
# Expected: Status: HEALTHY
```

---

## 6. Enable Elastic Defend (EDR) with kernel module monitoring

In Kibana:

1. **Security → Manage → Integrations → Elastic Defend → Add Elastic Defend**
2. Select policy: **All threat protections** (most aggressive for demo purposes)
3. Under **Advanced settings**, confirm these are enabled:
   - `linux.advanced.kernel.capture_mode: kprobe` 
   - Kernel telemetry: **Enabled**

### 6a. Enable the specific rule: "Kernel Module Load"

Navigate to:  
**Security → Rules → Detection rules → Search: "kernel module"**

Enable these rules:
- **Kernel Module Load via insmod**
- **Suspicious Kernel Module Load**
- **Kernel Module Load from Unusual Location** (optional)

Set them to **Enabled** if they aren't already.

### 6b. Confirm auditd integration (belt-and-suspenders)

Elastic Defend uses eBPF/kprobes for kernel telemetry, but auditd rules give an additional signal:

```bash
sudo apt install -y auditd
sudo auditctl -a always,exit -F arch=b64 -S init_module -S finit_module -k kernel_module_load
sudo auditctl -l | grep kernel_module_load
```

This ensures that even if eBPF misses the load, auditd generates an event that Elastic Agent will forward.

---

## 7. Resource check after all services are up

```bash
free -h
# You want at least 1–1.5 GB free for the demo to run smoothly

sudo systemctl status elasticsearch kibana elastic-agent
# All three should show: active (running)
```

If RAM is tight:
```bash
# Reduce Elasticsearch heap further
sudo sed -i 's/-Xms1g/-Xms768m/; s/-Xmx1g/-Xmx768m/' \
  /etc/elasticsearch/jvm.options.d/heap.options
sudo systemctl restart elasticsearch
```

---

## 8. Snapshot before demo

Once everything is running cleanly and you've confirmed Kibana loads:

```bash
# VMware: VM → Snapshot → Take Snapshot
# Name: "elastic-clean-baseline"
```

This is your demo starting point. Always revert to this before presenting.

---

## 9. Quick verification checklist

Run these before every demo session:

```bash
# Services up
sudo systemctl is-active elasticsearch kibana elastic-agent

# Elasticsearch responsive
curl -s -u elastic:HakiDemo2025! http://localhost:9200/_cluster/health \
  | python3 -m json.tool | grep status
# Expected: "green" or "yellow" (yellow is fine for single-node)

# Kibana reachable
curl -s -o /dev/null -w "%{http_code}" http://localhost:5601/api/status
# Expected: 200

# Agent healthy
sudo elastic-agent status | grep -E "Status|State"

# Detector clean before rootkit load
sudo python3 /home/ihab/Desktop/haki-demo/detector.py
# Expected: CLEAN
```

---

## 10. Known issues and workarounds

| Issue | Fix |
|-------|-----|
| Elasticsearch won't start: `max virtual memory areas too low` | `sudo sysctl -w vm.max_map_count=262144` and add to `/etc/sysctl.conf` for persistence |
| Kibana 5601 unreachable from Windows host | Check `server.host: "0.0.0.0"` in `kibana.yml`; check `ufw` rules: `sudo ufw allow 5601` |
| Agent enrollment fails: SSL error | Ensure `xpack.security.http.ssl.enabled: false` in `elasticsearch.yml` |
| Elastic Defend not loading on kernel 6.17 | Check `/var/log/elastic-agent/` — eBPF probe may need `CONFIG_BPF_SYSCALL=y` (verify: `zcat /proc/config.gz \| grep BPF_SYSCALL`) |
| High RAM usage crashing VM | Reduce ES heap to 512m; consider running Kibana on Windows host against VM ES |
