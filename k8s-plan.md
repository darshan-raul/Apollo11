=== Flutter Frontend


=== Go API backend 


=== Kafka: event processing


=== Python data analytics backend

init containers: check until databases are up

secrets: for db connections
configmap: env variables

=== Mongodb for nosql 
https://deeptiman.medium.com/mongodb-statefulset-in-kubernetes-87c2f5974821


=== Postgres for relational database


=== dash dashboard to see stats



BEST practices:

- liveness probe
- readliness probe
- startup probe
- security context
- Requests
- Limits
- NodeAffinity
- NodeSelector
- Tolerations
- Taints


(Namespace level) -- applies to all containers

- Limit range -- for each container
- Resource Quota - Applies to whole namespace
- Network policy's