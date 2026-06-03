{{- /*
Namespace helper templates
*/ -}}
{{- define "apollo11.namespaces" -}}
apiVersion: v1
kind: Namespace
metadata:
  name: {{ .Values.namespaces.infra }}
  labels:
    {{- include "apollo11.labels" . | nindent 4 }}
    stage: "5"
---
apiVersion: v1
kind: Namespace
metadata:
  name: {{ .Values.namespaces.apps }}
  labels:
    {{- include "apollo11.labels" . | nindent 4 }}
    stage: "5"
---
apiVersion: v1
kind: Namespace
metadata:
  name: {{ .Values.namespaces.ui }}
  labels:
    {{- include "apollo11.labels" . | nindent 4 }}
    stage: "5"
{{- end -}}

{{- /*
ServiceAccount helper templates
*/ -}}
{{- define "apollo11.serviceAccounts" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.serviceAccounts.infra }}
  namespace: {{ .Values.namespaces.infra }}
  labels:
    {{- include "apollo11.labels" . | nindent 4 }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.serviceAccounts.apps }}
  namespace: {{ .Values.namespaces.apps }}
  labels:
    {{- include "apollo11.labels" . | nindent 4 }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.serviceAccounts.ui }}
  namespace: {{ .Values.namespaces.ui }}
  labels:
    {{- include "apollo11.labels" . | nindent 4 }}
{{- end -}}

{{- /*
PriorityClass for app pods
*/ -}}
{{- define "apollo11.priorityClass" -}}
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: {{ .Values.priorityClassName }}
description: "Apollo11 app pods — scheduled before default priority"
value: 100000
globalDefault: false
{{- end -}}