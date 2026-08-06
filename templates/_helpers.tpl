{{/* Chart name. */}}
{{- define "openldap-iam.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Stable OpenLDAP resource prefix. */}}
{{- define "openldap-iam.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "openldap-iam.name" . }}
{{- end }}
{{- end }}

{{- define "openldap-iam.replicaName" -}}
{{- printf "%s-replica" (include "openldap-iam.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openldap-iam.readServiceName" -}}
{{- printf "%s-read" (include "openldap-iam.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openldap-iam.writeServiceName" -}}
{{- printf "%s-write" (include "openldap-iam.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openldap-iam.bootstrapName" -}}
{{- printf "%s-bootstrap" (include "openldap-iam.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openldap-iam.credentialsSecretName" -}}
{{- default (printf "%s-credentials" (include "openldap-iam.fullname" .)) .Values.credentials.existingSecret | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openldap-iam.tlsSecretName" -}}
{{- printf "%s-tls" (include "openldap-iam.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openldap-iam.caConfigMapName" -}}
{{- printf "%s-ca" (include "openldap-iam.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openldap-iam.primaryPVCName" -}}
{{- default (printf "%s-data" (include "openldap-iam.fullname" .)) .Values.primary.persistence.existingClaim | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openldap-iam.lamName" -}}
{{- default "ldap-account-manager" .Values.lam.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openldap-iam.lamPVCName" -}}
{{- default (printf "%s-data" (include "openldap-iam.lamName" .)) .Values.lam.persistence.existingClaim | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openldap-iam.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openldap-iam.labels" -}}
helm.sh/chart: {{ include "openldap-iam.chart" . }}
app.kubernetes.io/part-of: iam
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "openldap-iam.ldapSelectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: ldap-server
{{- end }}

{{- define "openldap-iam.primarySelectorLabels" -}}
{{ include "openldap-iam.ldapSelectorLabels" . }}
ldap-role: primary
{{- end }}

{{- define "openldap-iam.replicaSelectorLabels" -}}
{{ include "openldap-iam.ldapSelectorLabels" . }}
ldap-role: replica
{{- end }}

{{- define "openldap-iam.lamSelectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: ldap-account-manager
{{- end }}

{{- define "openldap-iam.writeURI" -}}
{{- printf "ldaps://%s.%s.svc.%s:%v" (include "openldap-iam.writeServiceName" .) .Release.Namespace .Values.clusterDomain .Values.services.write.port }}
{{- end }}

{{- define "openldap-iam.readURI" -}}
{{- printf "ldaps://%s.%s.svc.%s:%v" (include "openldap-iam.readServiceName" .) .Release.Namespace .Values.clusterDomain .Values.services.read.port }}
{{- end }}
