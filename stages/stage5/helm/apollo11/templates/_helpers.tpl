{{- /*
Common labels applied to all resources
*/ -}}
{{- define "apollo11.labels" -}}
app.kubernetes.io/name: apollo11
app.kubernetes.io/part-of: apollo11
hermes: managed
{{- end -}}

{{- /*
Selector labels for deployments/statefulsets
*/ -}}
{{- define "apollo11.selectorLabels" -}}
app.kubernetes.io/name: {{ .name | default .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}