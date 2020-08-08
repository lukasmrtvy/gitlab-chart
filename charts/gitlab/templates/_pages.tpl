{{/*
Generates pages configuration.
Usage:
{{ include "gitlab.appConfig.pages.configuration" $ }}
*/}}
{{- define "gitlab.appConfig.pages.configuration" -}}
pages:
  enabled: {{ eq $.Values.global.appConfig.pages.enabled true }}
  host: {{ $.Values.global.appConfig.pages.host }}
  port: {{ $.Values.global.appConfig.pages.port }}
  path: {{ $.Values.global.appConfig.pages.path }}
  https: {{ $.Values.global.appConfig.pages.https }}
{{- end -}}{{/* "gitlab.appConfig.pages.configuration" */}}
