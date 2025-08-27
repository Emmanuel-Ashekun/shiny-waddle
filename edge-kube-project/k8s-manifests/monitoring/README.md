# Monitoring (Prometheus & Grafana)
We recommend installing the kube-prometheus-stack via Helm on the central node:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f values.yaml
```

This values.yaml exposes Grafana via NodePort and enables scraping of kube-state-metrics to observe app versions and node status.