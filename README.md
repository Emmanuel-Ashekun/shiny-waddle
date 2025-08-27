# Edge Kube Project (Terraform · Ansible · KubeEdge · Prometheus/Grafana)

Spin up a **central** Kubernetes control-plane (K3s + KubeEdge CloudCore) and **three edge nodes** (KubeEdge EdgeCore) on AWS EC2, then deploy **five static web apps** and a **monitoring stack**. This repo is a minimal, hackable template you can adapt for demos and PoCs.

> **Why KubeEdge?** It keeps a single Kubernetes control plane in the “cloud” while edge nodes run workloads locally—even during outages. When connectivity returns, state re-syncs.

---

## Architecture

- **Central (cloud) node**: K3s (single‑node control plane) + **KubeEdge CloudCore**
- **Edge nodes (x3)**: **KubeEdge EdgeCore** + container runtime (containerd)
- **Apps**: 5 x static Nginx sites (ConfigMap content) exposed via NodePort
- **Monitoring**: Prometheus + Grafana (via kube‑prometheus‑stack Helm chart)

```
+-------------------+        TLS/Tunnel (10000)        +--------------------+
|   Central (EC2)   | <------------------------------> |   Edge (EC2) x3    |
|  K3s + CloudCore  |                                   | EdgeCore + Pods    |
|  Prometheus/Graf  |                                   | NodePorts 30001-5  |
+-------------------+                                   +--------------------+
```

---

## Repo Layout

```
terraform/                 # EC2, VPC/SG, AMI lookup (Ubuntu 22.04)
ansible/
  inventory.ini            # Fill with Terraform outputs
  playbook.yml             # Runs common -> master/edge roles
  roles/
    common/                # containerd, base packages, swapoff
    master/                # K3s control-plane + keadm init (CloudCore)
    edge/                  # keadm join (EdgeCore)
k8s-manifests/
  apps/                    # 5 static-site Deployments + Services (NodePort)
  monitoring/
    README.md              # Helm install notes
    values.yaml            # Grafana NodePort 30000
static-sites/              # Editable HTML content per site
```

---

## Prerequisites

- Terraform ≥ 1.5, Ansible ≥ 2.14, kubectl, Helm
- AWS account + existing key pair (`var.key_name`)
- Local machine with network access to EC2 public IPs
- **$ Costs**: EC2, EBS, data transfer. Destroy when done.

---

## Quick Start

### 1) Provision AWS infra
```bash
cd terraform
terraform init
terraform apply -auto-approve   -var="key_name=YOUR_KEYPAIR"   -var="region=us-east-1"
```
Outputs include **central** and **edge** public IPs.

### 2) Fill Ansible inventory
Edit `ansible/inventory.ini`:
```ini
[central]
central ansible_host=<CENTRAL_PUBLIC_IP> ansible_user=ubuntu

[edges]
edge1   ansible_host=<EDGE1_PUBLIC_IP>   ansible_user=ubuntu
edge2   ansible_host=<EDGE2_PUBLIC_IP>   ansible_user=ubuntu
edge3   ansible_host=<EDGE3_PUBLIC_IP>   ansible_user=ubuntu
```

### 3) Configure K3s + KubeEdge
```bash
cd ../ansible
ansible-playbook -i inventory.ini playbook.yml
```
What this does:
- Installs containerd (all nodes)
- Installs **K3s** + runs `keadm init` (CloudCore) on **central**
- Fetches a **join token** and runs `keadm join` (EdgeCore) on **edges**

Verify:
```bash
ssh ubuntu@<CENTRAL_PUBLIC_IP> 'sudo kubectl get nodes -o wide'
# You should see 1 master + 3 edge nodes (Ready)
```

### 4) Use kubeconfig
On central node the kubeconfig is at `/etc/rancher/k3s/k3s.yaml`.
```bash
# copy locally (example; adjust key path and IP)
scp -i ~/.ssh/YOUR_KEY.pem ubuntu@<CENTRAL_PUBLIC_IP>:/etc/rancher/k3s/k3s.yaml ./kubeconfig
export KUBECONFIG=$PWD/kubeconfig
```

### 5) Deploy the 5 apps
```bash
kubectl apply -f k8s-manifests/apps/
kubectl get pods -o wide
```
- Each app is a Deployment + NodePort Service (30001–30005).
- Optional: pin apps to specific edges (see **Node Placement** below).

### 6) (Optional) Monitoring stack
```bash
cd k8s-manifests/monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack   -n monitoring --create-namespace -f values.yaml
```
- Grafana on **NodePort 30000** (default admin/admin – change in `values.yaml`).

### 7) Test
- Apps: `http://<EDGE_PUBLIC_IP>:30001..30005`
- Grafana: `http://<CENTRAL_PUBLIC_IP>:30000`

---

## Node Placement (optional)

Label edge nodes and apply `nodeSelector` (uncomment in manifests):
```bash
kubectl label nodes edge1 site=edge1
kubectl label nodes edge2 site=edge2
kubectl label nodes edge3 site=edge3
# then edit k8s-manifests/apps/static-site*.yaml nodeSelector blocks
```

---

## App Versioning

Templates show a version in HTML. For better tracking via metrics:
- Add a label to Deployments, e.g. `app.kubernetes.io/version: "1.0.0"`
- Or build per-app images tagged with semantic versions and use those tags

Then query in Grafana/PromQL (kube‑state‑metrics):
```
kube_pod_container_info{pod=~"static-site.*"}
```

---

## Security & Hardening

This template is **open by default for demo speed**. For anything real:
- Restrict SG ingress to your IP/VPN; avoid 0.0.0.0/0 where possible
- Place EC2 in **private subnets**; use bastion / SSM Session Manager
- Terminate TLS and use mTLS between CloudCore and EdgeCore
- Store tokens/keys in AWS SSM Parameter Store / Secrets Manager
- Consider a **local registry mirror** at edges + image signing (Cosign)
- Enable audit logs, CIS benchmarks, and tighten RBAC

---

## Troubleshooting

- **Edges don’t show up**: check SG port **10000/tcp**, rerun `keadm gettoken` on central and re‑`keadm join` on edges.
- **Nodes NotReady**: `kubectl describe node <edge>`; verify EdgeCore is running (`systemctl status edgecore` if installed as service).
- **NodePorts unreachable**: confirm SG allows 30000–32767 and instance has public IP.
- **Metrics empty**: ensure kube‑prometheus‑stack installed; for full `kubectl top` with KubeEdge, deploy metrics‑server compatible with KubeEdge and enable cloud/edge stream features.
- **SSH auth**: use the same key pair you set in Terraform `var.key_name`.

---

## Customize

- Edit HTML in `static-sites/site*/index.html`
- Tune app manifests in `k8s-manifests/apps/*.yaml`
- Change counts/sizes in `terraform/variables.tf`
- Update versions in `ansible/group_vars/all.yml`

---

## Cleanup

```bash
cd terraform
terraform destroy -auto-approve
```

---

## Roadmap ideas

- Loki/Grafana for logs; alerts in Prometheus
- Private networking + WireGuard/VPN for edges
- Registry mirror + pre‑pulls for offline windows
- CI/CD (GitHub Actions) to rebuild images & apply manifests
- Swap K3s for EKS‑Anywhere or upstream kubeadm if needed

— © 2025 Edge Kube Project — MIT-style starter.
