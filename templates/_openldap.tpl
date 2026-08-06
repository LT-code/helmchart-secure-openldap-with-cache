{{/* Shared OpenLDAP Deployment fragments. */}}
{{- define "openldap-iam.openldapDeploymentLabels" -}}
{{- $root := .root -}}
{{ include "openldap-iam.labels" $root }}
app.kubernetes.io/name: openldap
app.kubernetes.io/component: ldap-server
ldap-role: {{ .role }}
{{ $root.Values.tls.rolloutLabel.key }}: {{ $root.Values.tls.rolloutLabel.value | quote }}
{{- end }}

{{- define "openldap-iam.openldapPodAnnotations" -}}
checksum/bootstrap: {{ include (print .Template.BasePath "/bootstrap-configmap.yaml") . | sha256sum }}
{{- if .Values.credentials.create }}
checksum/credentials: {{ include (print .Template.BasePath "/credentials-secret.yaml") . | sha256sum }}
{{- end }}
{{- end }}

{{- define "openldap-iam.openldapPodSettings" -}}
{{- $root := .root -}}
automountServiceAccountToken: false
terminationGracePeriodSeconds: {{ $root.Values.openldap.terminationGracePeriodSeconds }}
securityContext:
  {{- toYaml $root.Values.openldap.podSecurityContext | nindent 2 }}
{{- if .workload.affinity }}
affinity:
  {{- toYaml .workload.affinity | nindent 2 }}
{{- else if .defaultAntiAffinity }}
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            {{- include "openldap-iam.ldapSelectorLabels" $root | nindent 12 }}
        topologyKey: kubernetes.io/hostname
{{- end }}
{{- with .workload.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .workload.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "openldap-iam.openldapDirectoryEnv" -}}
{{- $root := .root -}}
- name: DOMAIN
  value: {{ $root.Values.directory.domain | quote }}
- name: BASE_DN
  value: {{ $root.Values.directory.baseDN | quote }}
- name: ORGANIZATION
  value: {{ .organization | quote }}
{{- if .includeOrganizationalUnits }}
- name: PEOPLE_OU
  value: {{ $root.Values.directory.peopleOU | quote }}
- name: GROUPS_OU
  value: {{ $root.Values.directory.groupsOU | quote }}
{{- end }}
{{- end }}

{{- define "openldap-iam.openldapCredentialsEnv" -}}
- name: ADMIN_PASS
  valueFrom:
    secretKeyRef:
      name: {{ include "openldap-iam.credentialsSecretName" . }}
      key: admin-password
- name: CONFIG_PASS
  valueFrom:
    secretKeyRef:
      name: {{ include "openldap-iam.credentialsSecretName" . }}
      key: config-password
{{- end }}

{{- define "openldap-iam.openldapSchemaEnv" -}}
- name: SCHEMA_TYPE
  value: {{ .Values.openldap.schemaType | quote }}
- name: ENABLE_PPOLICY
  value: {{ ternary "TRUE" "FALSE" .Values.openldap.enablePasswordPolicy | quote }}
{{- end }}

{{- define "openldap-iam.openldapTLSEnv" -}}
- name: ENABLE_TLS
  value: "TRUE"
- name: TLS_CREATE_SELFSIGNED
  value: "FALSE"
- name: TLS_CERT_PATH
  value: /certs/
- name: TLS_CERT_FILE
  value: cert.pem
- name: TLS_KEY_PATH
  value: /certs/
- name: TLS_KEY_FILE
  value: key.pem
- name: TLS_CA_NAME
  value: ldap-selfsigned-ca
- name: TLS_CA_CERT_PATH
  value: /certs/ldap-selfsigned-ca/
- name: TLS_CA_CERT_FILE
  value: ldap-selfsigned-ca.crt
- name: TLS_DH_PARAM_PATH
  value: /certs/
- name: TLS_DH_PARAM_FILE
  value: dhparam.pem
- name: TLS_ENABLE_DH_PARAM
  value: "TRUE"
- name: TLS_RESET_PERMISSIONS
  value: "FALSE"
- name: TLS_VERIFY_CLIENT
  value: {{ .Values.openldap.tlsVerifyClient | quote }}
- name: TLS_ENFORCE
  value: "TRUE"
- name: SLAPD_HOSTS
  value: "ldaps://0.0.0.0:636/ ldapi:///"
- name: LOG_TYPE
  value: {{ .Values.openldap.logType | quote }}
- name: REMOVE_CONFIG_AFTER_SETUP
  value: "false"
{{- end }}

{{- define "openldap-iam.openldapProbes" -}}
startupProbe:
  exec:
    command:
      - /bin/sh
      - -c
      - >-
        LDAPTLS_CACERT=/certs/ldap-selfsigned-ca/ldap-selfsigned-ca.crt
        LDAPTLS_REQCERT=demand ldapwhoami -x -H ldaps://localhost:636
        -D "cn=admin,$BASE_DN" -w "$ADMIN_PASS" >/dev/null
  failureThreshold: {{ .startupFailureThreshold }}
  periodSeconds: 5
  timeoutSeconds: 4
readinessProbe:
  exec:
    command:
      - /bin/sh
      - -c
      - >-
        LDAPTLS_CACERT=/certs/ldap-selfsigned-ca/ldap-selfsigned-ca.crt
        LDAPTLS_REQCERT=demand ldapwhoami -x -H ldaps://localhost:636
        -D "cn=admin,$BASE_DN" -w "$ADMIN_PASS" >/dev/null
  {{- with .readinessInitialDelaySeconds }}
  initialDelaySeconds: {{ . }}
  {{- end }}
  periodSeconds: 10
  timeoutSeconds: 4
  failureThreshold: 6
livenessProbe:
  tcpSocket:
    port: ldaps
  initialDelaySeconds: 30
  periodSeconds: 20
  timeoutSeconds: 3
  failureThreshold: 6
{{- end }}

{{- define "openldap-iam.openldapVolumeMounts" -}}
- name: data
  mountPath: /data
- name: bootstrap
  mountPath: /opt/bootstrap
  readOnly: true
- name: tls
  mountPath: /certs
  readOnly: true
{{- end }}

{{- define "openldap-iam.openldapSharedVolumes" -}}
- name: bootstrap
  configMap:
    name: {{ include "openldap-iam.bootstrapName" . }}
    defaultMode: 365
- name: tls
  secret:
    secretName: {{ include "openldap-iam.tlsSecretName" . }}
    defaultMode: 288
    items:
      - key: tls.crt
        path: cert.pem
      - key: tls.key
        path: key.pem
      - key: ca.crt
        path: ldap-selfsigned-ca/ldap-selfsigned-ca.crt
      - key: dhparam.pem
        path: dhparam.pem
{{- end }}
