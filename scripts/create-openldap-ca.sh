#!/usr/bin/env bash
set -euo pipefail
umask 077

NAMESPACE="${NAMESPACE:-iam}"
STATE_DIR="${STATE_DIR:-/var/lib/openldap-pki}"
CA_DAYS="${CA_DAYS:-3650}"
CA_CONFIGMAP="${CA_CONFIGMAP:-openldap-ca}"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

CA_KEY="$STATE_DIR/ca.key"
CA_CERT="$STATE_DIR/ca.crt"
DH_PARAMS="$STATE_DIR/dhparam.pem"
LDAP_CONF="$STATE_DIR/ldap.conf"

function create_config_map() {
  kubectl -n "$NAMESPACE" create configmap "$CA_CONFIGMAP" \
    --from-file=ca.crt="$CA_CERT" \
    --from-file=ldap.conf="$LDAP_CONF" \
    --dry-run=client -o yaml | kubectl apply -f -
}

if [[ -e "$CA_KEY" || -e "$CA_CERT" ]]; then
  create_config_map
  echo "CA already exists in $STATE_DIR; keeping it untouched."
  exit 0
fi

openssl req -x509 -new -nodes \
  -newkey rsa:4096 \
  -sha256 \
  -days "$CA_DAYS" \
  -subj "/CN=OpenLDAP Internal CA/O=IAM" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -keyout "$CA_KEY" \
  -out "$CA_CERT"

# Generated once and reused by the LDAP servers.
openssl dhparam -out "$DH_PARAMS" 4096

cat > "$LDAP_CONF" <<'LDAPEOF'
TLS_CACERT /etc/ldap/openldap-trust/ca.crt
TLS_REQCERT demand
LDAPEOF

chmod 600 "$CA_KEY"
chmod 644 "$CA_CERT" "$DH_PARAMS" "$LDAP_CONF"

# Publish only the public CA and LDAP client settings.
create_config_map

echo "CA created in $STATE_DIR"
echo "Back up $CA_KEY securely. Do not delete or regenerate it."

