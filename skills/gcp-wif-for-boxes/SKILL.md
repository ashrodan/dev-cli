---
name: gcp-wif-for-boxes
description: Give an exe.dev VM short-lived GCP credentials through Workload Identity Federation, so no service-account key ever lands on the box. Use when a VM needs BigQuery, Storage or any GCP API, when replacing a GOOGLE_APPLICATION_CREDENTIALS key file, or when a WIF setup returns permission errors that are really trust-configuration errors.
allowed-tools: Bash, Read
argument-hint: [gcp-project] [vm]
---

# gcp-wif-for-boxes

Federation replaces the key file. The VM mints a short-lived exe.dev OIDC token,
Google trusts that token through a Workload Identity Pool, and the VM
impersonates a service account for a few minutes at a time. Nothing on disk can
leak, because nothing on disk is a credential.

Two halves that must agree exactly:

```
exe.dev integration  ──token──>  GCP pool provider  ──impersonate──>  service account
   (issuer, subject)              (trust rule)                        (the IAM identity)
```

Almost every failure is those halves disagreeing, and **every one of them
surfaces as a permissions error** regardless of the real cause. Diagnose the
trust chain before touching IAM roles.

## When to invoke

- A VM needs to reach GCP and you are about to copy a `*.json` key. Stop.
- Replacing an existing `GOOGLE_APPLICATION_CREDENTIALS` key file.
- `iam.serviceAccounts.getAccessToken` denied, or `/token` returns "not found".

## Never

- Never copy a service-account key or `application_default_credentials.json` to
  a box. The first is a permanent credential, the second is your personal Google
  identity, and every agent on that box can read both.
- Never reuse another integration's issuer/subject. Each one has its own.

## 1. Create the exe.dev integration

Web UI, choosing the **GCP** provider (the form defaults can land you on AWS).
Inputs: project ID, project number, pool ID, provider ID, and the service
account email — the SA need not exist yet.

Decide **team vs personal now**, because it changes the hostname the VM fetches
tokens from and that URL gets baked into the credential file:

```
personal   https://<name>.int.exe.xyz
team       https://<name>.team.exe.xyz
```

**Team integrations only attach to tags.** `vm:<name>` is rejected outright.
Attach to a tag the VM already carries rather than inventing one:

```bash
ssh <lobby> "integrations list" | grep <name>     # see current attachments
ssh <lobby> "ls --json"                           # see what tags a VM has
ssh <lobby> "integrations attach <name> tag:<existing-tag>"
```

Allow ~20 seconds. Until it propagates, `/token` returns "team integration not
found or not attached to this VM", which reads like a configuration error and
is not one.

## 2. GCP side

`bin/exe-gcp-wif` does it idempotently — APIs, pool, provider, service account
and the impersonation binding:

```bash
exe-gcp-wif --project <gcp-project> --sa <name> \
  --issuer https://exe.dev/issuer/<slug> --subject sub-XXXX \
  --audience "<from the integration>" --bq-job-user --dry-run
```

Use the audience the integration reports, not a derived guess. `integrations
list` prints it:

```
gcpwif  wif  audience=https://iam.googleapis.com/projects/.../providers/exe-dev ttl=5m consumer=gcp
```

**Two audience formats, both correct, easily confused.** The JWT's `aud` claim
is `https://iam.googleapis.com/...` and the provider's `--allowed-audiences`
must match it exactly. The credential config file uses `//iam.googleapis.com/...`
— `create-cred-config` writes that one itself.

## 3. Verify the subject against a live token

**The single highest-value step.** The subject displayed while creating an
integration is not necessarily the one its VMs present. Bind the wrong one and
you get a permission denial that no amount of role-granting fixes.

```bash
ssh <vm> 'curl -sS https://<name>.team.exe.xyz/token' |
  python3 -c 'import base64,json,sys
t=json.load(sys.stdin)["token"].split(".")[1]; t+="="*(-len(t)%4)
c=json.loads(base64.urlsafe_b64decode(t))
print("iss", c["iss"]); print("sub", c["sub"]); print("aud", c["aud"])'
```

Compare `sub` with what is bound:

```bash
gcloud iam service-accounts get-iam-policy <sa-email> --project <p> --format=json
```

If they differ, bind the real one and drop the stale one:

```bash
POOL=projects/<number>/locations/global/workloadIdentityPools/<pool>
gcloud iam service-accounts add-iam-policy-binding <sa-email> --project <p> \
  --role roles/iam.workloadIdentityUser \
  --member "principal://iam.googleapis.com/${POOL}/subject/<REAL-SUBJECT>"
gcloud iam service-accounts remove-iam-policy-binding <sa-email> --project <p> \
  --role roles/iam.workloadIdentityUser \
  --member "principal://iam.googleapis.com/${POOL}/subject/<STALE-SUBJECT>"
```

`/metadata` on the same host echoes the pool, project and SA the integration
believes it is for — worth a glance against your own values.

## 4. Credential config on the VM

The file holds **no secret** — only the URL to fetch a fresh token from — so it
can be generated anywhere and copied.

```bash
export EXE_WIF_URL="https://<name>.team.exe.xyz"
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcloud/exe-<name>-gcp-wif.json"
mkdir -p "$(dirname "$GOOGLE_APPLICATION_CREDENTIALS")"
gcloud iam workload-identity-pools create-cred-config \
  projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/<provider> \
  --service-account <sa-email> \
  --credential-source-url "$EXE_WIF_URL/token" \
  --credential-source-type json --credential-source-field-name token \
  --output-file "$GOOGLE_APPLICATION_CREDENTIALS"
```

## 5. Verify, knowing the two consumers differ

**Client libraries** (Go, Python, Node) read `GOOGLE_APPLICATION_CREDENTIALS`
directly. No code change, nothing further to do.

**The `gcloud`/`bq` CLIs ignore it.** They need to be logged in explicitly:

```bash
gcloud auth login --cred-file="$GOOGLE_APPLICATION_CREDENTIALS"
gcloud config set account <sa-email>       # auth list shows ACTIVE while
gcloud config set project <project>        # core/account is still unset
```

Then prove the whole chain with something real:

```bash
bq --project_id=<project> query --nouse_legacy_sql \
  'SELECT COUNT(*) FROM `bigquery-public-data.thelook_ecommerce.orders`'
```

Expect a denial on the first attempt — a fresh `workloadIdentityUser` binding
takes 20–40s to take effect. Retry before re-configuring anything.

## Permissions, once the identity works

BigQuery splits access in two, granted in different places:

| grant | where | gives |
|---|---|---|
| `roles/bigquery.jobUser` | project billing the query | run jobs; no data |
| `roles/bigquery.dataViewer` | the dataset holding the data | read rows |
| `roles/bigquery.metadataViewer` | project or dataset | schemas, no rows |

`metadataViewer` project-wide plus `dataViewer` on named datasets is a good
default for an agent: it can discover structure everywhere and read values only
where you said so.

**Public datasets need no grant.** `bigquery-public-data.thelook_ecommerce`
carries `allUsers: READER`, so `jobUser` on your billing project is the entire
permission set. Check before granting:

```bash
bq show --format=prettyjson bigquery-public-data:<dataset> | grep -A2 iamMember
```

## Failure modes, and what they actually mean

| symptom | cause |
|---|---|
| `/token` → "not found or not attached" | not attached, wrong hostname (int vs team), or <20s since attaching |
| `iam.serviceAccounts.getAccessToken` denied | subject mismatch, or binding <40s old |
| STS `Invalid value for "audience"` | `//` vs `https://` form confusion |
| `gcloud` "no active account" but `auth list` shows one | `core/account` unset |
| project IAM binding: "service account does not exist" | SA created seconds ago; retry |

## Notes

IAM propagates slowly in two separate places — after creating a service account,
and after binding a principal to it. Both look like misconfiguration and neither
is. Retry with backoff; `bin/exe-gcp-wif` does this for project bindings.

AWS works the same way with a role ARN instead of a service account, trusting
the same issuer through an IAM OIDC provider. The trust-chain reasoning and the
failure modes are identical.
