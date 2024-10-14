# Prometheus

- setup using simple k8s manifests
- persistence using pvc
- how to instrument apps to have a /metrics endpoints
- basics of prometheus metrics
- using alert manager to send email/slack alerts


# Grafana

- setup using simple k8s manifests

https://grafana.com/docs/grafana/latest/setup-grafana/installation/kubernetes/

- persistence using pvc
- auto provisioning data sources

https://grafana.com/docs/grafana/latest/administration/provisioning/

- auto provisioning dashboards/plugins/alerting rules





# To send a test log message to loki

```
curl -v -H "Content-Type: application/json" -XPOST -s "http://localhost:3100/loki/api/v1/push" --data-raw \
 '{"streams": [{ "stream": { "foo": "bar2" }, "values": [ [ "1728922776000000000", "fizzbuzz" ] ] }]}'

```

> Replace  1728922776000000000 with the relevant epoch time 

You should be able to see the logs in loki as below

![alt text](image.png)