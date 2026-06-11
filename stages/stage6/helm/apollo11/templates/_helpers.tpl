{{- /*
Common labels applied to all resources. These are the standard
app.kubernetes.io/* labels — they show up in `kubectl get --show-labels`,
in tools like k9s, and are used by Prometheus/Grafana to group resources.
*/ -}}
{{- define "apollo11.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: apollo-airlines
hermes: managed
{{- end -}}

{{- /*
Selector labels — stable across upgrades, used in matchLabels.
Do NOT add version/instance to selectors; doing so breaks rolling
updates when the chart version changes.
*/ -}}
{{- define "apollo11.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- /*
Workload selector for a given app — used by Deployments / StatefulSets.
Each app carries an `app: <name>` label that matches the Service selector.
*/ -}}
{{- define "apollo11.appSelector" -}}
app: {{ .name }}
{{- end -}}

{{- /*
Common pod labels — adds tier to the standard set.
  tier: public   for user-facing apps (identity, flight, booking, search, notification, frontend)
  tier: data     for stateful workloads (postgres, redis)
*/ -}}
{{- define "apollo11.podLabels" -}}
{{- $root := .root -}}
{{- $tier := .tier | default "public" -}}
app: {{ .name }}
tier: {{ $tier }}
app.kubernetes.io/name: {{ $root.Chart.Name }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ $root.Release.Service }}
app.kubernetes.io/part-of: apollo-airlines
hermes: managed
{{- end -}}

{{- /*
ServiceAccount name for a workload. Centralised so the helper
templates can refer to the same SA consistently.
*/ -}}
{{- define "apollo11.serviceAccountName" -}}
{{- default .name .serviceAccount.name -}}
{{- end -}}
