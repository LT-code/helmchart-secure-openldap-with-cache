# openldap-iam Helm chart

This chart installs:

- One read/write OpenLDAP Deployment with an NFS CSI PVC.
- One read-only OpenLDAP syncrepl consumer with node-local `emptyDir` storage.
- `openldap-read`, which load-balances LDAPS connections across both LDAP pods.
- `openldap-write`, which selects only the primary.
- LDAP Account Manager connected to the write Service.
- Optional `nfs-csi-fast-safe` StorageClass creation.
- LDAPS only on port 636.

## 1. Create the CA once

```bash
kubectl create namespace iam --dry-run=client -o yaml | kubectl apply -f -
STATE_DIR=$PWD/.openldap-pki NAMESPACE=iam ./scripts/create-openldap-ca.sh
```

Keep and back up `.openldap-pki/ca.key`. The CA defaults to ten years.

## 2. Create the server certificate

```bash
STATE_DIR=$PWD/.openldap-pki NAMESPACE=iam ./scripts/update-openldap-certificate.sh
```

The certificate contains the DNS names for `openldap-read` and `openldap-write` and creates `Secret/openldap-tls`.

## 3. Install

From the packaged chart:

```bash
helm upgrade --install openldap ./openldap-iam-0.1.0.tgz \
  --namespace iam \
  --create-namespace \
  --values values-production.yaml
```

## Endpoints

```text
ldaps://openldap-read.iam.svc.cluster.local:636
ldaps://openldap-write.iam.svc.cluster.local:636
```

Clients must trust the public CA from `ConfigMap/openldap-ca` or from `.openldap-pki/ca.crt`.

## LAM

```bash
kubectl -n iam port-forward svc/ldap-account-manager 8080:80
```

Open `http://localhost:8080`. The LDAP administrator DN is `cn=admin,dc=example,dc=internal` with the configured admin password.

## Daily certificate renewal

Run `scripts/update-openldap-certificate.sh` daily. It renews only when the certificate is near expiry. When renewed, it restarts deployments selected by:

```text
openldap-tls-reload=true
```

Example cron command:

```cron
15 2 * * * STATE_DIR=/var/lib/openldap-pki NAMESPACE=iam KUBECONFIG=/root/.kube/config /opt/openldap-iam/scripts/update-openldap-certificate.sh >> /var/log/openldap-certificate.log 2>&1
```

## Important settings

- `replica.requireDifferentNode=true` requires at least two schedulable nodes.
- The replica has no PVC and fully resynchronizes after pod replacement.
- Both persistent PVCs explicitly use `nfs-csi-fast-safe` by default.
- If `fullnameOverride` changes, pass matching `READ_SERVICE` and `WRITE_SERVICE` values to the certificate script.
- StorageClass and PVC resources use `helm.sh/resource-policy: keep` by default.
- Set `credentials.create=false` and `credentials.existingSecret` to use an externally managed password Secret.
