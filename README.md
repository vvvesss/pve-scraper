# Proxmox VM Scraper for Prometheus

## Overview

This project provides a Ruby-based scraper that dynamically discovers Proxmox VE virtual machines and registers them as Prometheus scrape targets using [http_sd_configs](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#http_sd_config). It allows precise monitoring of each VM using node_exporter, enabling integration with Grafana dashboards and Prometheus alerting.

### Why Use This?

Monitor VMs as Standalone Instances: Unlike Proxmox's [exporter](https://github.com/prometheus-pve/prometheus-pve-exporter) (which are very nice btw, but aggregates metrics at the host level), this setup provides granular VM monitoring.
Dynamic Service Discovery: Automatically updates Prometheus targets when VMs are created or removed.
Tag-Based Labeling: Uses Proxmox VM tags as Prometheus labels for better organization.
The scraper extracts VM tags from Proxmox and transforms them into Prometheus labels using a structured format. Each tag follows this convention:
```
labelname---labelvalue
```
For example, if a VM in Proxmox has the following tags:
```
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
This approach ensures:
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

## Installation

### 1. Deploy Scraper in Kubernetes
Apply the Kubernetes deployment from this repository:
```
kubectl apply -f k8s/scraper-deployment.yaml
```

### 2. Install node_exporter on VMs
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

### 3. Configure Prometheus

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

### 4. Verify the Setup
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

