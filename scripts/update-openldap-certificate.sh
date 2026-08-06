#!/usr/bin/env bash
set -euo pipefail
umask 077

NAMESPACE="${NAMESPACE:-iam}"
STATE_DIR="${STATE_DIR:-/var/lib/openldap-pki}"
TLS_SECRET="${TLS_SECRET:-openldap-tls}"
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-cluster.local}"
READ_SERVICE="${READ_SERVICE:-openldap-read}"
WRITE_SERVICE="${WRITE_SERVICE:-openldap-write}"
CERT_DAYS="${CERT_DAYS:-90}"
RENEW_BEFORE_DAYS="${RENEW_BEFORE_DAYS:-30}"
ROLLOUT_SELECTOR="${ROLLOUT_SELECTOR:-openldap-tls-reload=true}"

CA_KEY="$STATE_DIR/ca.key"
CA_CERT="$STATE_DIR/ca.crt"
DH_PARAMS="$STATE_DIR/dhparam.pem"
SERVER_KEY="$STATE_DIR/tls.key"
SERVER_CERT="$STATE_DIR/server.crt"
SERVER_CHAIN="$STATE_DIR/tls.crt"
CSR="$STATE_DIR/server.csr"
CONF="$STATE_DIR/server.cnf"

for file in "$CA_KEY" "$CA_CERT" "$DH_PARAMS"; do
  [[ -s "$file" ]] || { echo "Missing $file. Run create-openldap-ca.sh first." >&2; exit 1; }
done

if [[ -s "$SERVER_CERT" ]] && \
   openssl x509 -checkend "$((RENEW_BEFORE_DAYS * 86400))" -noout -in "$SERVER_CERT" >/dev/null 2>&1 && \
   kubectl -n "$NAMESPACE" get secret "$TLS_SECRET" >/dev/null 2>&1; then
  echo "Certificate is still valid; nothing to do."
  exit 0
fi

cat > "$CONF" <<EOFCONF
[req]
prompt = no
distinguished_name = dn
req_extensions = extensions

[dn]
CN = ${WRITE_SERVICE}.${NAMESPACE}.svc.${CLUSTER_DOMAIN}
O = IAM

[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @names

[names]
DNS.1 = ${READ_SERVICE}
DNS.2 = ${WRITE_SERVICE}
DNS.3 = ${READ_SERVICE}.${NAMESPACE}
DNS.4 = ${WRITE_SERVICE}.${NAMESPACE}
DNS.5 = ${READ_SERVICE}.${NAMESPACE}.svc
DNS.6 = ${WRITE_SERVICE}.${NAMESPACE}.svc
DNS.7 = ${READ_SERVICE}.${NAMESPACE}.svc.${CLUSTER_DOMAIN}
DNS.8 = ${WRITE_SERVICE}.${NAMESPACE}.svc.${CLUSTER_DOMAIN}
DNS.9 = localhost
IP.1 = 127.0.0.1
EOFCONF

openssl req -new -nodes \
  -newkey rsa:3072 \
  -keyout "$SERVER_KEY" \
  -out "$CSR" \
  -config "$CONF"

openssl x509 -req \
  -in "$CSR" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -days "$CERT_DAYS" \
  -sha256 \
  -extfile "$CONF" \
  -extensions extensions \
  -out "$SERVER_CERT"

cat "$SERVER_CERT" "$CA_CERT" > "$SERVER_CHAIN"
rm -f "$CSR"
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_CERT" "$SERVER_CHAIN"

openssl verify -CAfile "$CA_CERT" "$SERVER_CERT"

kubectl -n "$NAMESPACE" create secret generic "$TLS_SECRET" \
  --from-file=tls.crt="$SERVER_CHAIN" \
  --from-file=tls.key="$SERVER_KEY" \
  --from-file=ca.crt="$CA_CERT" \
  --from-file=dhparam.pem="$DH_PARAMS" \
  --dry-run=client -o yaml | kubectl apply -f -

DEPLOYMENTS="$(kubectl -n "$NAMESPACE" get deployment -l "$ROLLOUT_SELECTOR" -o name)"
if [[ -n "$DEPLOYMENTS" ]]; then
  kubectl -n "$NAMESPACE" rollout restart deployment -l "$ROLLOUT_SELECTOR"
fi

echo "Secret/$TLS_SECRET updated."
