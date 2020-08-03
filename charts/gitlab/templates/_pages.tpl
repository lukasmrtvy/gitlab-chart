{{/*
Generates pages configuration.
Usage:
{{ include "gitlab.appConfig.pages.configuration" $ }}
*/}}
{{- define "gitlab.appConfig.pages.configuration" -}}
pages:
  enabled: {{ eq $.Values.global.appConfig.pages.enabled true }}
{{- end -}}{{/* "gitlab.appConfig.pages.configuration" */}}
