## Making cluster prod grade


### Using node affinity

```
nodeSelector:  # Assign pods to specific nodes if necessary
disktype: ssd  # Example node selector label
affinity:  # Use node affinity/anti-affinity for better control over pod placement
podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
            - key: app
            operator: In
            values:
                - dashboard
        topologyKey: "kubernetes.io/hostname"
tolerations:  # Handle taints on nodes for specific tolerations
- key: "node.kubernetes.io/memory-pressure"
    operator: "Exists"
    effect: "NoSchedule"
```


### Adding deployment strategy

```
strategy:  # Add a rolling update strategy to ensure smooth updates
    type: RollingUpdate
    rollingUpdate:
        maxSurge: 25%  # Allows 25% additional pods during updates
        maxUnavailable: 25%  # Ensures that at least 75% of the pods are running
```