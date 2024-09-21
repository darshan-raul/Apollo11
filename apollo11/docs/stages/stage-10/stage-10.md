## Adding security context

```
securityContext:  # Add security context for container security
runAsNonRoot: true  # Ensure the container runs as a non-root user
capabilities:
    drop:
    - ALL  # Drop all Linux capabilities unless needed
```