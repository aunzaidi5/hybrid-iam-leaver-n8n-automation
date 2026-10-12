# Hybrid IAM Leaver Automation

A hands-on hybrid identity lab that disables an Active Directory account, removes its AWS access-group membership, revokes Microsoft Entra sessions through Microsoft Graph, and records the leaver event through n8n, Slack, Google Sheets and a locally generated email summary.

**Author:** Aun Zaidi Â· **Environment:** AWS-hosted hybrid identity lab Â· **Scope:** employee offboarding demonstration

![Final n8n workflow with Microsoft Graph, Slack, Google Sheets and Ollama email branches](screenshots/30-Final-n8n-Workflow.png)

*Figure 30 â€” The supplied final workflow. Ollama supplies the language model to the summary chain; n8n sends the email. Separate screenshots below document Slack and Sheets delivery.*

**Start here:** [Architecture](#architecture) Â· [Leaver workflow](#leaver-workflow) Â· [Test results](#test-results--evidence) Â· [Reproduction](#how-to-reproduce) Â· [Workflow import](n8n/README.md) Â· [Security and limitations](docs/security-and-limitations.md)

> This repository documents a completed lab using supplied implementation screenshots and project notes. The public PowerShell and Compose files are sanitized recreations of the documented setup; the n8n JSON is derived from the supplied export. Public-version adjustments are listed in the [import guide](n8n/README.md#changes-from-the-supplied-export). These public files have not been rerun against the live identity environment.

## Project Goal

When an employee leaves, disabling one account does not necessarily remove every entitlement or invalidate every active session. The goal is to demonstrate a traceable offboarding process across an AD identity source, Entra and AWS, with explicit boundaries between account state, entitlement propagation, session revocation and operational notifications.

The test identity, **Omar Malik**, first received AWS `ViewOnlyAccess` through the synchronized `SG-AWS-Lab-Users` group. A manually invoked leaver script then changed the authoritative AD state and triggered n8n. Cloud Sync and SCIM propagated the entitlement change independently of the notification workflow.

## What This Project Demonstrates

| Component | Role in this lab |
|---|---|
| Active Directory and PowerShell | Authoritative identity/group state; direct membership removal and account disablement |
| Microsoft Entra Cloud Sync | Synchronization from AD to Entra |
| SAML SSO | Federated authentication between Entra and AWS IAM Identity Center |
| SCIM provisioning | User and group provisioning from Entra into AWS IAM Identity Center |
| AWS IAM Identity Center | Group-based AWS account access through a permission set |
| Microsoft Graph | Dynamic user lookup and session revocation using app-only authentication |
| n8n | Webhook processing, API calls, audit preparation and notification branches |
| Slack and Google Sheets | Operational alert and append-only workflow operation to a lab audit sheet |
| Ollama | Local `qwen2.5:3b` summary generation; no identity administration tools |
| SMTP | Delivery of the generated summary by n8n |
| Docker | Persistent n8n and Ollama containers on the Ubuntu host |

## Architecture

```mermaid
flowchart TD
    AD["DC01: AD DS and PowerShell"]
    ENTRA["Microsoft Entra ID"]
    AWS["AWS IAM Identity Center"]
    N8N["N8N01: n8n on Docker"]
    OLLAMA["Ollama: qwen2.5:3b"]
    SLACK["Slack"]
    SHEETS["Google Sheets"]
    EMAIL["SMTP email"]
    AD -->|Entra Cloud Sync| ENTRA
    ENTRA -->|SAML SSO| AWS
    ENTRA -->|SCIM provisioning| AWS
    AD -->|PowerShell webhook event| N8N
    N8N -->|Graph lookup and revocation| ENTRA
    N8N -->|Alert| SLACK
    N8N -->|Audit row| SHEETS
    N8N <-->|Summary request and response| OLLAMA
    N8N -->|Generated summary| EMAIL
```

AD is authoritative for the synchronized user and group. Entra handles cloud identity, federation and Graph session revocation. AWS consumes provisioning through SCIM. n8n orchestrates the response and reporting; it does **not** directly remove users or memberships in AWS.

| Resource | Recorded lab configuration |
|---|---|
| Hosting | AWS EC2 |
| VPC / subnet | `10.30.0.0/16` / `10.30.1.0/24` |
| DC01 | Windows Server 2025, `10.30.1.10`, AD DS, DNS, Cloud Sync agent, PowerShell |
| AD domain | `iam.automation` |
| AD organization | `OU=Corporate` with `Users`, `Groups`, and `Service Accounts` child OUs |
| AWS entitlement group | `SG-AWS-Lab-Users`, global security group sourced from AD |
| N8N01 | Ubuntu, `10.30.1.20`, Docker, n8n and Ollama |
| Container model endpoint | `http://ollama:11434`, reachable from n8n on the Compose network |
| Model | `qwen2.5:3b` |

Private addresses describe the recorded topology; the PowerShell script takes its webhook URL from configuration.

## Identity Provisioning Foundation

### Federation and initial cloud-only provisioning

The first stage exchanged AWS service-provider metadata and Entra identity-provider metadata, configured SAML, and validated the SCIM connection. A cloud-only group named `AWS-Lab-Users` was used to establish provisioning and portal access. It is distinct from the later AD-synchronized `SG-AWS-Lab-Users` group.

SAML authenticates a user. SCIM creates and updates directory objects and memberships. A successful SAML setup alone does not provision a user or grant an AWS account permission set.




![Figure 01: AWS service-provider metadata is available for download, including issuer and ACS URLs.](screenshots/01-AWS-Download-Metadata.png)

*Figure 01 â€” AWS service-provider metadata is available for download, including issuer and ACS URLs.*

![Figure 02: Importing AWS metadata into the Entra enterprise application.](screenshots/02-Entra-Upload-Metadata.png)

*Figure 02 â€” Importing AWS metadata into the Entra enterprise application.*

![Figure 03: SAML identifiers, reply URLs and access-portal sign-on URL configured in Entra.](screenshots/03-SAML-Configuration.png)

*Figure 03 â€” SAML identifiers, reply URLs and access-portal sign-on URL configured in Entra.*

![Figure 04: AWS external identity-provider confirmation screen after selecting Entra metadata; this is a review step, not an AD domain trust.](screenshots/04-AWS-External-Identity-Provider-Review.png)

*Figure 04 â€” AWS external identity-provider confirmation screen after selecting Entra metadata; this is a review step, not an AD domain trust.*

![Figure 05: Entra SCIM test connection succeeds. The secret-token field is masked.](screenshots/05-Entra-SCIM-Connection-Success.png)

*Figure 05 â€” Entra SCIM test connection succeeds. The secret-token field is masked.*

![Figure 06: Initial AWS-Lab-Users group in Entra: Source is Cloud. This is not the later AD-synced group.](screenshots/06-Entra-Cloud-Only-Lab-Group.png)

*Figure 06 â€” Initial AWS-Lab-Users group in Entra: Source is Cloud. This is not the later AD-synced group.*

![Figure 07: Entra reports Start provisioning successful; the screen still says the initial sync has not run.](screenshots/07-Entra-Start-Provisioning.png)

*Figure 07 â€” Entra reports Start provisioning successful; the screen still says the initial sync has not run.*

![Figure 08: Initial cloud-only group assigned to the AWS enterprise application.](screenshots/08-Entra-Enterprise-App-Group-Assignment.png)

*Figure 08 â€” Initial cloud-only group assigned to the AWS enterprise application.*

![Figure 09: AWS-Lab-Users appears in Identity Center with Created by SCIM and one member.](screenshots/09-AWS-SCIM-Group-Provisioned.png)

*Figure 09 â€” AWS-Lab-Users appears in Identity Center with Created by SCIM and one member.*

![Figure 10: Initial cloud-only test identity can see ViewOnlyAccess in the AWS access portal.](screenshots/10-AWS-Initial-ViewOnlyAccess.png)

*Figure 10 â€” Initial cloud-only test identity can see ViewOnlyAccess in the AWS access portal.*




### AD-sourced hybrid identity

The second stage introduced the `iam.automation` domain, Cloud Sync, Omar's synchronized identity, and the AD-sourced security group. `ViewOnlyAccess` was assigned to that group for the AWS account, and Omar could see the entitlement in the access portal before offboarding.

The Cloud Sync configuration screenshot captures a **Disabled** configuration during setup. The next screenshot proves successful **on-demand** user provisioning; it should not be presented as proof that the scheduled synchronization configuration was healthy at that earlier moment.




![Figure 11: AD Domains and Trusts console shows the iam.automation domain on DC01.](screenshots/11-Active-Directory-Domain.png)

*Figure 11 â€” AD Domains and Trusts console shows the iam.automation domain on DC01.*

![Figure 12: Cloud Sync configuration for AD to Entra, captured while Disabled during setup.](screenshots/12-Entra-Cloud-Sync-Configuration.png)

*Figure 12 â€” Cloud Sync configuration for AD to Entra, captured while Disabled during setup.*

![Figure 13: On-demand Cloud Sync successfully creates Omar in Entra and shows AccountEnabled=True.](screenshots/13-Entra-On-Demand-User-Provisioning.png)

*Figure 13 â€” On-demand Cloud Sync successfully creates Omar in Entra and shows AccountEnabled=True.*

![Figure 14: Omar appears in AWS IAM Identity Center with Created by SCIM and Enabled status.](screenshots/14-AWS-Omar-Provisioned.png)

*Figure 14 â€” Omar appears in AWS IAM Identity Center with Created by SCIM and Enabled status.*

![Figure 15: Review of the AD-synced SG-AWS-Lab-Users assignment to the ViewOnlyAccess permission set.](screenshots/15-AWS-Synced-Group-Permission-Set.png)

*Figure 15 â€” Review of the AD-synced SG-AWS-Lab-Users assignment to the ViewOnlyAccess permission set.*

![Figure 16: Omar has ViewOnlyAccess available before offboarding.](screenshots/16-AWS-Omar-Access-Before-Offboarding.png)

*Figure 16 â€” Omar has ViewOnlyAccess available before offboarding.*




## Automation Infrastructure

DC01 and N8N01 run in the lab subnet. The domain controller runs the AD commands and submits the event. The Ubuntu instance runs both containers, with persistent volumes at `/home/node/.n8n` and `/root/.ollama`.

The supplied [Compose baseline](docker/compose.yaml) publishes n8n on TCP 5678 and does not publish an Ollama host port. n8n reaches Ollama using Docker service discovery. EC2 security groups and the host firewall must restrict 5678 to approved sources. Production requires a TLS endpoint and authenticated webhook. The Compose file does not provision AWS networking or a reverse proxy.

`latest` tags match the requested lab baseline, but do not lock the original runtime. Pin tested image versions or digests for a repeatable deployment.




![Figure 17: Initial n8n/Ollama chat test succeeds; this is an integration smoke test, not the leaver workflow.](screenshots/17-n8n-Ollama-Integration.png)

*Figure 17 â€” Initial n8n/Ollama chat test succeeds; this is an integration smoke test, not the leaver workflow.*

![Figure 18: Ubuntu shell shows both containers running, the model downloaded and an Ollama response. Ollama has no published host port.](screenshots/18-Docker-n8n-Ollama-Running.png)

*Figure 18 â€” Ubuntu shell shows both containers running, the model downloaded and an Ollama response. Ollama has no published host port.*




## Leaver Workflow

### PowerShell on DC01

[Invoke-IAMLeaver.ps1](powershell/Invoke-IAMLeaver.ps1) accepts a `SamAccountName` and a configured webhook URL. It validates configuration, imports the AD module, resolves the user and group, removes direct membership when present, disables the account, and POSTs the event only after those operations succeed.

The script adds `-WhatIf`, confirmation support, UTC timestamps, optional webhook header authentication, a delivery timeout and stage-specific failure messages. Its error path does not undo successful AD changes. It deliberately does not silently retry delivery because a timeout can occur after n8n has already accepted an event.

Only direct membership in the named group is handled. Other groups, nested entitlements, primary-group membership and direct AWS assignments require additional scope and controls.

```mermaid
flowchart TD
    START["Run leaver script"] --> AD["Remove direct group membership and disable AD user"]
    AD --> EVENT["POST leaver event to n8n"]
    EVENT --> GRAPH["Resolve Entra user and revoke sessions"]
    GRAPH --> RECORD["Prepare audit record"]
    RECORD --> SLACK["Slack alert"]
    RECORD --> SHEET["Append audit row"]
    RECORD --> SUMMARY["Generate summary with Ollama"]
    SUMMARY --> MAIL["Send SMTP email"]
    AD --> SYNC["Cloud Sync and SCIM propagation"]
    SYNC --> AWS["AWS group entitlement removed after propagation"]
```

The diagram separates the API/notification path from entitlement synchronization. An accepted webhook is not evidence that either path has finished.

### Every n8n node

| Node in the supplied export | Responsibility |
|---|---|
| **Webhook** | Accepts a POST at `iam-leaver`. The exported lab node has no webhook authentication configured. |
| **Edit Fields** | Reads `samAccountName`, `displayName`, `userPrincipalName`, `department`, and `disabledAt` from the request body. It maps fields; it is not a schema-validation gate. |
| **Find Entra User** | URL-encodes the supplied UPN and requests the user dynamically from Graph. No test user's object ID is hardcoded. |
| **Revoke Entra Sessions** | Uses the returned Entra ID in `POST /users/{id}/revokeSignInSessions`. |
| **Prepare Leaver Audit Record** | Combines the original fields, `entraUserId`, the Graph result in `entraSessionsRevoked`, and `workflowStatus`. |
| **Send a message** | Sends a deterministic Slack alert using the prepared record. It does not use the AI output. |
| **Append row in sheet** | Appends the mapped eight-column record to the configured Google Sheet. |
| **Generate AI Leaver Summary** | Uses the prepared record and a constrained prompt to create a readable summary. |
| **Ollama Chat Model** | Supplies `qwen2.5:3b` to the summary chain through an `ai_languageModel` connection. It is not a later sequential action. |
| **Send an Email** | Uses SMTP to email the summary chain's `text` output. |

The three branches share an audit record; the export does not implement durable branch isolation, completion aggregation or compensating actions. `Leaver processing initiated` is intentionally not an assertion that AWS propagation and every notification have completed.

## Microsoft Graph Integration

The lab app registration is **IAM-Leaver-n8n**. The two HTTP Request nodes use an n8n OAuth2 credential with the client-credentials grant and Graph application permissions.

| Permission visible in the lab | Use |
|---|---|
| `User.Read.All` â€” Application | Dynamic directory user lookup |
| `User.RevokeSessions.All` â€” Application | Session revocation request |
| `GroupMember.ReadWrite.All` â€” Application | Configured in the lab, but unused by this exported workflow; remove it for this scope |
| `User.Read` â€” Delegated | Also visible in the screenshot; not used by the client-credentials flow |

Grant admin consent for required application permissions. Configure the credential privately with the tenant-specific token URL `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token`, the app client ID, a secret, and scope `https://graph.microsoft.com/.default`. No credential values are included in this repository.

```http
GET https://graph.microsoft.com/v1.0/users/{URL-encoded-UPN}?$select=id,displayName,userPrincipalName,accountEnabled
POST https://graph.microsoft.com/v1.0/users/{returned-id}/revokeSignInSessions
```

Graph's revocation operation invalidates Entra refresh tokens and browser session cookies by advancing the user's session-validity timestamp. It can take a few minutes to apply. The lab received `{"value":true}`; that response is not an AWS session-revocation result. See [Microsoft's API reference](https://learn.microsoft.com/en-us/graph/api/user-revokesigninsessions?view=graph-rest-1.0).




![Figure 19: Graph application permissions granted to IAM-Leaver-n8n; the unused group-write and delegated permissions are also visible.](screenshots/19-Entra-Graph-App-Permissions.png)

*Figure 19 â€” Graph application permissions granted to IAM-Leaver-n8n; the unused group-write and delegated permissions are also visible.*




## Downstream AWS Deprovisioning

1. Remove Omar's membership in `SG-AWS-Lab-Users` in AD.
2. Entra Cloud Sync propagates that membership change to Entra.
3. Entra's SCIM provisioning propagates the change to AWS IAM Identity Center.
4. Once the membership change is processed, Omar can no longer obtain `ViewOnlyAccess` **through that group**.

This is asynchronous. A complete leaver process must also inspect other group grants and direct assignments. This workflow does not poll AWS, verify all entitlements, delete the AWS user, or terminate AWS sessions.

Existing AWS access-portal and role sessions have their own lifecycle. A blocked fresh Entra login does not demonstrate termination of an already-issued AWS STS/role session. Stronger revocation requires [AWS-side access and session controls](https://docs.aws.amazon.com/singlesignon/latest/userguide/revoke-user-permissions.html).

## Notifications and Audit

Slack carries an operational alert; Google Sheets stores the structured lab record; Ollama generates a human-readable summary that n8n emails through SMTP. The public workflow reports the actual Graph boolean in Slack and asks the model to preserve that distinction.

| Google Sheets column | Audit-record field |
|---|---|
| Timestamp | `disabledAt` |
| User | `displayName` |
| Username | `samAccountName` |
| UPN | `userPrincipalName` |
| Department | `department` |
| Entra User ID | `entraUserId` |
| Sessions Revoked | `entraSessionsRevoked` |
| Status | `workflowStatus` |

AI has no identity-management tools or authority. Its prose is not authoritative audit evidence. The original email prompt used Slack-style formatting, which explains the literal asterisks in the captured email; the public version requests plain text.




![Figure 26: Slack receives the IAM leaver notification. The original message contains fixed success statements; the public export reports the actual Graph result.](screenshots/26-Slack-Leaver-Notification.png)

*Figure 26 â€” Slack receives the IAM leaver notification. The original message contains fixed success statements; the public export reports the actual Graph result.*

![Figure 27: n8n maps the eight audit fields and displays the Google Sheets append output.](screenshots/27-n8n-Google-Sheets-Mapping.png)

*Figure 27 â€” n8n maps the eight audit fields and displays the Google Sheets append output.*

![Figure 28: Google Sheets contains the lab leaver audit record with Sessions Revoked=TRUE.](screenshots/28-Google-Sheets-Audit-Record.png)

*Figure 28 â€” Google Sheets contains the lab leaver audit record with Sessions Revoked=TRUE.*

![Figure 29: Received email containing the Ollama-generated leaver summary. Its prose is not independent evidence of downstream completion.](screenshots/29-Ollama-Email-Delivered.png)

*Figure 29 â€” Received email containing the Ollama-generated leaver summary. Its prose is not independent evidence of downstream completion.*




## Test Results / Evidence

The screenshots cover multiple implementation and test iterations, not one timestamp-correlated production run. The following table separates visible results from outcomes described in the supplied lab notes.

| Check | Evidence and interpretation |
|---|---|
| Omar exists and is enabled in AD; direct AWS group membership exists | Figure 20 shows `Enabled=True` and the group member list. |
| Omar provisioned to Entra | Figure 13 shows successful on-demand creation. |
| Omar provisioned to AWS | Figure 14 lists Omar as enabled and created by SCIM. |
| Group permission set and pre-offboarding portal access | Figures 15â€“16 show the assignment setup and Omar's `ViewOnlyAccess` entry. |
| AD disablement and membership removal | Figure 21 shows script output, `Enabled=False`, and no members returned by the group query. |
| n8n webhook, dynamic Graph lookup and revocation | Figure 22 shows successful execution through these nodes and Graph `value=true`; the JSON supplies the dynamic lookup expression. |
| Entra group membership removed | Figure 24 shows the actual `SG-AWS-Lab-Users` Members page with zero members. |
| SCIM update and AWS group reaching zero members | Reported in the project notes. No supplied screenshot directly shows the post-offboarding AWS membership view or successful SCIM update log. |
| Fresh sign-in attempt blocked | Figure 25 shows Entra's account-locked message during the reported fresh AWS portal sign-in attempt. It does not identify the precise lock/disable cause or prove existing AWS sessions ended. |
| Slack delivery | Figure 26 shows the received leaver alert. |
| Sheets mapping and audit row | Figures 27â€“28 show mapping output and the stored row. |
| AI summary and email delivery | Figure 29 shows the delivered summary; Figure 30 shows the chain and email branch. |

One original screenshot numbered 23 shows a broad group search returning no results. That is weaker evidence than the actual group Members page; it is retained with an explicit caption. The other original 23 was labelled as AWS but visibly shows Entra. Filenames have been normalized to match the contents rather than perpetuate that label.




![Figure 20: Before-state: Omar is enabled in AD and is a direct member of SG-AWS-Lab-Users.](screenshots/20-AD-Before-Leaver.png)

*Figure 20 â€” Before-state: Omar is enabled in AD and is a direct member of SG-AWS-Lab-Users.*

![Figure 21: PowerShell removes membership and disables Omar; verification returns Enabled=False and an empty group member list.](screenshots/21-AD-Leaver-Script-Result.png)

*Figure 21 â€” PowerShell removes membership and disables Omar; verification returns Enabled=False and an empty group member list.*

![Figure 22: n8n receives the event, looks up the Entra user and completes revocation with value=true. n8n is not shown disabling AD.](screenshots/22-n8n-Entra-Session-Revocation.png)

*Figure 22 â€” n8n receives the event, looks up the Entra user and completes revocation with value=true. n8n is not shown disabling AD.*

![Figure 23: A broad Entra group search returns no results. This search alone does not establish membership removal.](screenshots/23-Entra-Group-Search-No-Results.png)

*Figure 23 â€” A broad Entra group search returns no results. This search alone does not establish membership removal.*

![Figure 24: The actual Entra SG-AWS-Lab-Users Members page shows zero members. The original filename incorrectly called this an AWS screenshot.](screenshots/24-Entra-SG-AWS-Lab-Users-Membership-Removed.png)

*Figure 24 â€” The actual Entra SG-AWS-Lab-Users Members page shows zero members. The original filename incorrectly called this an AWS screenshot.*

![Figure 25: Fresh sign-in is blocked at Entra with an account-locked message; this is not an AWS session-termination result.](screenshots/25-Entra-Fresh-Sign-In-Blocked.png)

*Figure 25 â€” Fresh sign-in is blocked at Entra with an account-locked message; this is not an AWS session-termination result.*




## Security Considerations

- Keep client secrets, Slack tokens, SMTP passwords, Google OAuth secrets and n8n encryption material out of Git. Rebind credentials after import and manage production secrets through a vault.
- Use HTTPS and authenticate the webhook. Restrict who can invoke an operation that revokes sessions; validate payloads and allowed targets. The supplied lab webhook does not provide those controls.
- Restrict security groups, host firewalls and administrative access. Keep Ollama off public host ports.
- Grant only required Graph application permissions. AD remains authoritative for the synchronized group.
- Treat AI as a summary writer. Directory fields are untrusted input; model output must not drive actions or declare success.
- Apply access controls, retention, monitoring and SIEM/ITSM integration to production audit records and n8n execution data.

All 30 screenshots were visually inspected before publication; no visible credential value was found. Some screenshots retain non-secret lab identifiers and contact details. The [privacy inventory](docs/security-and-limitations.md#screenshot-review-and-privacy-inventory) identifies the affected groups of images. Screenshots are unchanged evidence, not sanitized configuration examples.

## Known Limitations

1. Entra Cloud Sync and SCIM are asynchronous; propagation latency is not measured here.
2. `revokeSignInSessions` does not guarantee immediate termination of existing AWS STS/role sessions.
3. Google Sheets is a mutable lab audit store, not an enterprise SIEM or immutable event ledger.
4. Development used n8n's test webhook. This is not a production-grade deployment claim.
5. Production needs a published workflow, production `/webhook/` URL, HTTPS and authentication/signing.
6. PowerShell is manually invoked for the demo.
7. An HR/ITSM trigger, scheduled detection, event source or service is future work.
8. Durable state, retries, idempotency, dead-letter handling and full failure orchestration are not implemented.
9. AD changes can succeed while webhook delivery fails or times out. Reconciliation must check both systems before replay.
10. Ollama is only used for summarization; generated text can still be wrong.
11. The lab covers one directly assigned AD group and one test identity, not every application or access path.
12. The export lacks an explicit branch that handles Graph returning false, as distinct from an HTTP error. The public messages preserve the returned value, but escalation requires further implementation.
13. n8n trusts the incoming AD event; it does not independently verify account disablement or membership state. The webhook has no schema validation or replay protection.
14. Public scripts/configuration have static checks only in this publishing environment; Windows AD, Docker and authenticated integration tests must be run in a dedicated lab.

## Production Improvements

These are proposed improvements, not completed features:

- Integrate ServiceNow/HR events and privileged-identity approval controls, with manager/application-owner workflows where required.
- Publish the workflow behind TLS and add API/header authentication or HMAC signing with timestamp/replay validation.
- Add a durable event/outbox store, correlation IDs, idempotency keys, bounded retries and dead-letter handling.
- Validate Graph results, isolate notification failures, create incident tickets and monitor workflow health.
- Reconcile authoritative AD state, Entra synchronization and downstream SCIM results before marking offboarding complete.
- Extend entitlement cleanup to multiple groups, direct assignments and application-specific access.
- Send authoritative audit events to Microsoft Sentinel or another SIEM; apply retention and tamper-resistance controls.
- Use managed secrets, credential rotation, tested container versions, backups and restore tests.
- Implement AWS-side session controls when immediate interruption of existing access is required.

## Repository Structure

| Path | Contents |
|---|---|
| `README.md` | Architecture, workflow explanation, evidence and reproduction steps |
| `LICENSE` | MIT license for repository code and documentation; third-party products retain their own licenses |
| `.gitignore` | Excludes environment files, keys, credential folders, backups and logs |
| `powershell/Invoke-IAMLeaver.ps1` | Sanitized leaver script with configurable webhook endpoint |
| `docker/compose.yaml` | n8n and Ollama lab services with persistent volumes |
| `docker/.env.example` | Non-secret timezone defaults |
| `n8n/User-Leaver-Automation.json` | Sanitized, inactive workflow derived from the actual export |
| `n8n/README.md` | Credential rebinding, import procedure and public-version change list |
| `samples/leaver-payload.json` | Fictional event payload |
| `screenshots/` | 30 sequentially numbered implementation images |
| `docs/security-and-limitations.md` | Trust boundaries, failure modes, privacy inventory and evidence caveats |

## How to Reproduce

Use an isolated environment and a disposable test identity. This is a manual lab guide, not infrastructure-as-code provisioning.

1. **Provision the lab.** Create the VPC/subnet and two hosts, install AD DS/DNS on DC01, create the domain/OUs and global security group, and configure an AD UPN suffix compatible with your Entra tenant. Use delegated permissions for the script operator.
2. **Establish hybrid identity.** Install/configure Cloud Sync with appropriate scope. Enable and validate the configuration; an on-demand test alone does not verify continuing synchronization.
3. **Configure Entra and AWS.** Exchange SAML metadata, configure SCIM with privately stored credentials, assign the synchronized group to the enterprise app and an AWS account permission set, and verify the test user's pre-offboarding access.
4. **Start the runtime** on N8N01 from the repository root:

   ```bash
   cd docker
   cp .env.example .env
   docker compose up -d
   docker compose exec ollama ollama pull qwen2.5:3b
   docker compose ps
   ```

   Do not run `docker compose down -v` unless you intend to delete persistent data. Restrict port 5678 before starting. For initial administration, use an SSH tunnel to access `http://localhost:5678`; supply your own host and SSH configuration. The baseline does not set up TLS.

5. **Configure n8n.** Create the owner account, import the JSON, rebind Graph/Slack/Sheets/Ollama/SMTP credentials and destinations using the [import guide](n8n/README.md). Set the Ollama base URL to `http://ollama:11434`. Create the eight audit column headers exactly as shown above.
6. **Test the webhook deliberately.** In development, select Listen for Test Event and copy the `/webhook-test/iam-leaver` URL. For ongoing use, configure TLS and authentication, publish the workflow and copy its `/webhook/iam-leaver` URL. If using a reverse proxy, set n8n's external webhook URL appropriately; this is additional configuration.
7. **Configure PowerShell** on DC01 with a real reachable endpoint. The following is a placeholder HTTPS example, not a deployed service:

   ```powershell
   $env:N8N_LEAVER_WEBHOOK_URL = 'https://n8n.example.com/webhook/iam-leaver'
   # If Header Auth is configured, load N8N_LEAVER_WEBHOOK_TOKEN securely.
   .\powershell\Invoke-IAMLeaver.ps1 -SamAccountName 'jdoe' -WhatIf
   .\powershell\Invoke-IAMLeaver.ps1 -SamAccountName 'jdoe'
   ```

   `-WhatIf` performs configuration and AD reads without mutations or a POST. `-AllowInsecureHttp` is an explicit exception for private, isolated lab testing; it refuses to send a configured token over HTTP. The final command requests confirmation before changes.

8. **Verify both paths.** Confirm AD account state/group membership, inspect the n8n execution and Graph result, check Slack/Sheets/email, then inspect Entra and AWS memberships and provisioning logs. Attempt a fresh sign-in. Assess already-issued AWS sessions separately.
9. **Test failure cases before expansion.** Cover unknown UPN, missing permissions, Graph false/error responses, delivery timeouts, individual notification failures, duplicate events and synchronization outages. Record run-specific evidence and correlation IDs.

The [sample payload](samples/leaver-payload.json) documents the contract. Posting it directly skips AD changes and may attempt Graph revocation for its UPN; it is not proof that any AD operation occurred.

## Lessons Learned

- **SAML and SCIM solve different problems.** Federation establishes authentication; provisioning supplies the identities and memberships that authorization uses.
- **Source of authority matters.** Change synchronized group membership in AD and observe downstream results rather than attempting cloud-side edits to AD-owned state.
- **Hybrid timing is observable work.** A webhook response, Graph response and SCIM completion are distinct milestones.
- **Application permissions need deliberate scope.** The Graph app runs without a signed-in administrator; unnecessary group-write permission increases exposure without helping this flow.
- **Disablement, revocation and entitlement removal are separate controls.** None should be used as shorthand for all access being gone.
- **Audit trails need outcomes, not just messages.** Capture source facts, API results, propagation results and failures separately. An AI summary cannot replace them.
- **Retries need state.** A lost acknowledgement can cause duplicate processing; durable events and reconciliation are as important as the happy path.

### Technical references

- [Microsoft Graph: revokeSignInSessions](https://learn.microsoft.com/en-us/graph/api/user-revokesigninsessions?view=graph-rest-1.0)
- [AWS IAM Identity Center: revoke user access](https://docs.aws.amazon.com/singlesignon/latest/userguide/revoke-user-permissions.html)
- [n8n: Webhook node and test/production URLs](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)
- [n8n: Docker installation](https://docs.n8n.io/hosting/installation/docker/)

