# Import and configure the leaver workflow

[User-Leaver-Automation.json](User-Leaver-Automation.json) is a sanitized derivative of the **actual supplied 10-node export**. Its node types, versions, positions and connections are retained. It is inactive and has no attached credentials. It requires configuration before execution.

## Import

1. Start n8n and Ollama using [compose.yaml](../docker/compose.yaml), then pull `qwen2.5:3b` into the Ollama container.
2. In n8n, import the JSON from file. Keep it unpublished until credentials, destinations and webhook controls have been configured.
3. If a node version is unsupported by your n8n installation, use a compatible tested version or review/migrate that node explicitly. The source export does not identify its exact n8n container version; `latest` is not a compatibility guarantee.
4. Create credentials inside your n8n instance and bind them to the nodes listed below. Credential labels and IDs from the author's instance were removed.
5. Configure the Slack destination, Google spreadsheet/tab, and SMTP sender/recipient. Replace all `REPLACE_WITH_...` values and example email addresses.
6. Validate with a disposable identity. Importing or publishing does not prove that the flow has run successfully.

## Credential and destination mapping

| Node | Required configuration |
|---|---|
| Webhook | Lab export: POST, path `iam-leaver`, no authentication. For ongoing use, select Header Auth and create the matching credential. |
| Find Entra User | Generic OAuth2 API credential using Microsoft client credentials |
| Revoke Entra Sessions | Bind the same Graph credential |
| Send a message | Slack API credential with permission to post in your chosen channel; replace `REPLACE_WITH_SLACK_CHANNEL_ID` and give the bot access to that channel |
| Append row in sheet | Google Sheets OAuth2 credential for an account with access to the sheet; replace `REPLACE_WITH_GOOGLE_SPREADSHEET_ID`; select/enter your actual tab name (`Log1` is the example) |
| Ollama Chat Model | Ollama credential with base URL `http://ollama:11434`; model `qwen2.5:3b` |
| Send an Email | SMTP credential, provider host/port/TLS settings and privately stored password; set a valid sender and intended operations recipient |

Credentials are stored by n8n, not in Compose or the workflow JSON. Back up its persistent data and encryption material securely. A credential export or database backup must never be committed here.

### Microsoft Graph OAuth2

Create the `IAM-Leaver-n8n` app registration in your own tenant. Configure the n8n generic OAuth2 credential:

| Field | Value |
|---|---|
| Grant type | Client Credentials |
| Access token URL | `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token` |
| Client ID | Your app registration's client ID |
| Client secret | Stored only in the private n8n credential |
| Scope | `https://graph.microsoft.com/.default` |
| Client authentication | Body, so the client ID/secret are included in the token request form |

Grant admin consent for `User.Read.All` and `User.RevokeSessions.All` application permissions. The lab screenshot also shows `GroupMember.ReadWrite.All` and delegated `User.Read`; neither is used by this flow. Changes to synchronized group membership originate in AD.

The lookup uses the incoming UPN, URL-encoded for the Graph path. The revocation node uses the lookup result's `id`. No tenant ID, client ID or test-user object ID is embedded in those expressions.

### Webhook authentication and transport

The original lab node is deliberately represented without authentication; this is a documented limitation. It must not be exposed as an unrestricted internet endpoint.

For Header Auth, set the credential header name to `X-IAM-Webhook-Token` and choose a private random value. Load the same value into `N8N_LEAVER_WEBHOOK_TOKEN` for the PowerShell process through your approved secret mechanism. The public script supports that header. Do not pass secrets in URL query strings, commit them to `.env.example`, or print them in logs.

During development, listen for a test event and copy the test URL from the node. After configuring HTTPS/authentication, publish the workflow and use the production URL:

| Mode | Typical path | Requirement |
|---|---|---|
| Development | `/webhook-test/iam-leaver` | Test listener active |
| Published workflow | `/webhook/iam-leaver` | Workflow published; endpoint reachable |

Configure the reverse proxy/external webhook URL separately when deploying behind TLS. The Compose baseline does not supply a proxy. API/header authentication is not replay protection; HMAC, timestamps and durable event IDs are future improvements.

### Payload and audit sheet

The [sample](../samples/leaver-payload.json) has five fields: `samAccountName`, `displayName`, `userPrincipalName`, `department`, and ISO-8601 `disabledAt`. The current Edit Fields node maps them but does not enforce required-field validation.

Create these exact Google Sheets headers:

| Column | Header |
|---|---|
| A | Timestamp |
| B | User |
| C | Username |
| D | UPN |
| E | Department |
| F | Entra User ID |
| G | Sessions Revoked |
| H | Status |

The audit Set node adds the dynamic Entra ID, the Graph result and `Leaver processing initiated`. That status records a stage; it does not mean all downstream actions completed.

## Changes from the supplied export

| Change | Reason |
|---|---|
| Removed credential objects from all nodes | Avoid publishing instance-specific credential references; requires explicit rebinding |
| Removed workflow ID, version ID, instance metadata and node webhook IDs; set `active=false` | Avoid carrying runtime identity/activation state into a new installation |
| Removed Google cached destination names/URLs and replaced spreadsheet/channel IDs | Avoid targeting the author's actual destinations |
| Replaced sender/recipient with `example.com` addresses | Remove personal email addresses from executable configuration |
| Changed the email subject from a fixed test-user name to an expression | Correctly label each event |
| Normalized the audit field name `=displayName` to `displayName` | Ensure a plain field key matching downstream consumers |
| Changed `entraSessionsRevoked` from string to boolean | Preserve the Graph response type in the audit record |
| Updated Slack text to show the actual Graph result | Avoid unconditional revocation-success statements |
| Updated the AI prompt to request plain-text email output and distinguish source-reported AD state, Graph results and unverified AWS propagation | Match the actual email destination and reduce unsupported claims |

The 10-node graph and the three notification/audit branches have not been replaced with an invented design. No error-handler, approval, polling, validation or idempotency nodes are represented as implemented.

These public-version changes have been statically checked but not executed against the author's live integrations. The screenshots show the original lab versions and their outputs.

## Verify an execution

Inspect the webhook body, mapped fields, returned Entra user ID and Graph `value`. Confirm the prepared record contains a `displayName` field and a boolean `entraSessionsRevoked`. Check each notification/audit node independently and confirm actual Slack, Sheets and email delivery.

Check AD, Entra membership and AWS membership separately. The workflow does not measure SCIM completion. Do not treat a generated email, early HTTP acknowledgement, green upstream node or `workflowStatus` value as global success.

| Symptom | Check |
|---|---|
| Webhook returns not found | Test versus production path, active test listener, published workflow and proxy routing |
| Graph cannot find the user | Correct synchronized UPN, completed provisioning and URL expression |
| Graph returns 401/403 | Token audience/scope, application permission consent, secret expiry and tenant configuration |
| Ollama connection/model error | Both containers running, base URL uses `ollama` rather than localhost, model pulled into the persistent volume |
| Sheets append fails | Authorized account, spreadsheet access, selected tab and exact column headers |
| Slack/SMTP error | Credential binding, bot/channel access, provider TLS settings and sender authorization |
| AD changed but no workflow result | Check n8n executions before replaying the event; a timeout may hide a successful submission |

Do not include tokens, secrets or credential exports in troubleshooting issues.
