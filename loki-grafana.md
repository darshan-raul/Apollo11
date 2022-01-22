helm repo add grafana https://grafana.github.io/helm-charts
helm repo list
helm repo update
helm search repo grafana
helm upgrade --install loki grafana/loki-stack --namespace=loki --set grafana.enabled=true
kubectl port-forward service/loki-grafana 8443:80 -n loki
