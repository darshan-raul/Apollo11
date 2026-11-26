{{- /*
Common labels applied to all resources.
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
Common pod labels — adds tier to the standard set.
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
TODO (2): Define `apollo11.releaseAnnotations` here so it renders:
  apollo.airlines/release-channel: "<channel>"
from `(dict "channel" $appCfg.releaseChannel)`.
*/ -}}
