# Proxmox VM Scraper for Prometheus

## Overview

This project provides a Ruby-based scraper that dynamically discovers Proxmox VE virtual machines and registers them as Prometheus scrape targets using [http_sd_configs](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#http_sd_config). It allows precise monitoring of each VM using node_exporter, enabling integration with Grafana dashboards and Prometheus alerting.

### Why Use This?

Monitor VMs as Standalone Instances: Unlike Proxmox's [exporter](https://github.com/prometheus-pve/prometheus-pve-exporter) (which are very nice btw, but aggregates metrics at the Proxmox VE node level), this setup provides granular VM monitoring by using node exporter full on each VM.
The other use cases are when you need to use other custom exporters.
Dynamic Service Discovery: Automatically updates Prometheus targets when VMs are created or removed.
Tag-Based Labeling: Uses Proxmox VM tags as Prometheus labels for better organization.
The scraper extracts VM tags from Proxmox and transforms them into Prometheus labels using a structured format. Each tag follows this convention:

LabelName---LabelValue

### Example Tags:

os---ubuntu

osver---22.04lts

project---xrp-mainnet

type---blockchain


```
"labels": {
  "os": "ubuntu",
  "osver": "22.04lts",
  "project": "xrp-mainnet",
  "type": "blockchain"
}
```
### This approach ensures:


✅ Consistent Labeling – Every tag follows the same key-value structure.

✅ Flexible Filtering – You can group, filter, or alert on VMs based on OS, project, or type.

✅ Dynamic Discovery – Any updates to VM tags in Proxmox automatically reflect in Prometheus.


This structure allows for precise monitoring and alerting using Grafana dashboards and Prometheus queries like:
```
node_load1{project="xrp-mainnet"}
```

### How It Works

The scraper queries Proxmox VE API to fetch VM details and their assigned tags.
It transforms the data into Prometheus HTTP SD format.

Prometheus dynamically discovers the VMs using:
```
- job_name: 'pvm'
  scrape_interval: "20s"
  scrape_timeout: "5s"
  http_sd_configs:
    - url: "http://scraper-server.monitoring-gce.svc.cluster.local:9108"
      refresh_interval: "1m"
```

Each VM must have [node_exporter](https://github.com/prometheus/node_exporter) installed and running.

### Example Output Format
The scraper serves a JSON response at port 9108 in the following format:

```
[
  {
    "targets": [
      "192.168.210.3:9100"
    ],
    "labels": {
      "vm_id": "100",
      "pvehost": "sx04",
      "name": "tron-nile-1",
      "ip": "192.168.210.3",
      "instance": "tron-nile-1",
      "exporter": "node_exporter",
      "os": "ubuntu",
      "osver": "22.04lts",
      "project": "xrp-mainnet",
      "type": "blockchain"
    }
  }
]
```
##To collect data from the Proxmox API, you need to create a dedicated user in the **PVE** realm (not **PAM**). The PVE realm is recommended because it is native to Proxmox and independent of external authentication sources.

### Creating a Proxmox User:
1. Navigate to **Datacenter → Permissions → Users** in the Proxmox UI.
2. Click **Add** and create a new user:
   - **User**: `prometheus-scraper`
   - **Realm**: `PVE`
   - **Password**: Set a secure password.

### Assigning Permissions:
The user needs specific privileges to read VM and infrastructure data. Assign the following roles to the user:

- `Mapping.Audit`
- `VM.Monitor`
- `Pool.Audit`
- `Datastore.Audit`
- `SDN.Audit`
- `VM.Audit`
- `Sys.Audit`

You can do this via the Proxmox UI under **Datacenter → Permissions**, or using the Proxmox shell:

```sh
pveum user add prometheus-scraper@pve --password 'your-secure-password'
pveum aclmod / -user prometheus-scraper@pve -role PVEAuditor
```

This ensures the scraper can collect VM metadata while maintaining security by using minimal permissions.


## Installation

### 1. Setup Environment variables in deployments/pve-scraper.yaml
```
    spec:
      containers:
      - name: pve-scraper
        env:
          - name: USER
            value: "your-username"
          - name: PASS
            value: "your-password"
          - name: PROXMOX_URL
            value: "https://default-proxmox-url:8006/api2/json"
          - name: INTERVAL
            value: "60"
```
Optional: You can check for other ways to iject secrets in the deployment
Check for Hashicorp Vault or Kubernetes secrets options to do this in deployments/pve-scraper-templates.yaml

### 2. Deploy Scraper in Kubernetes
Apply the Kubernetes deployment from this repository:
```
kubectl apply -f deployments/pve-scraper.yaml
```

### 3. Install node_exporter on VMs
Run the following commands inside each VM:
```
wget https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-linux-amd64.tar.gz
tar xvf node_exporter-linux-amd64.tar.gz
sudo mv node_exporter-linux-amd64/node_exporter /usr/local/bin/
sudo useradd -rs /bin/false node_exporter
sudo tee /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

### 4. Configure Prometheus

Modify your Prometheus configuration to include:
```
scrape_configs:
  - job_name: 'pvm'
    scrape_interval: "20s"
    scrape_timeout: "5s"
    http_sd_configs:
      - url: "http://scraper-server.scraper-server-namespace.svc.cluster.local:9108"
        refresh_interval: "1m"
```

### 5. Verify the Setup
Check from inside your k8s if Prometheus has discovered the VMs:
```
curl http://scraper-server.scraper-server-namespace.svc.cluster.local:9108 | jq
```
Then, confirm in Prometheus UI under Status > Targets.

Grafana Dashboards
You can import the Node Exporter Full Dashboard from Grafana Labs:

[Node Exporter Full Dashboard](https://grafana.com/grafana/dashboards/1860-node-exporter-full/)

License
MIT License

