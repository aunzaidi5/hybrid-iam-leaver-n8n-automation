# Security, limitations and evidence review

This is an IAM portfolio lab, not a production offboarding service. The screenshots describe recorded lab behavior. Public code/configuration was recreated or sanitized for publication; production improvements are proposals.

## Trust boundaries

| Boundary | Current behavior | Production requirement |
|---|---|---|
| Operator to AD | Manual PowerShell invocation using operator rights | HR/ITSM source, delegated service identity, approvals for privileged targets |
| AD to n8n | A five-field event is POSTed after local changes; exported webhook has no auth | TLS, authenticated source, schema/target validation, replay protection and durable delivery |
| n8n to Graph | App-only lookup and revocation | Least-privilege consent, managed credential lifecycle and API-result checks |
| AD to Entra to AWS | Cloud Sync and SCIM propagate changes asynchronously | Monitor both provisioning stages and reconcile target state |
| n8n to reporting systems | Slack, mutable Sheets row and SMTP email | Restricted destinations, retention, SIEM/ITSM records and failure tracking |
| Audit record to Ollama | Directory fields and results supplied as text to a local model | Minimize personal data, treat fields as untrusted input and keep model output non-authoritative |

Local inference avoids sending the prompt to a hosted model provider, but the resulting summary leaves the host through email. Slack and Google Sheets also receive identity information. Local AI therefore does not imply that all event data stays local.

## Secrets and runtime configuration

- The workflow export contains no credential definitions or secret values. Rebind Graph, Slack, Google Sheets, Ollama and SMTP credentials in the destination n8n instance.
- `.env.example` contains only timezone defaults. The PowerShell endpoint and optional authentication token come from parameters/environment configuration.
- Keep n8n's persistent data, encryption material and backups private. Losing or changing encryption material can prevent stored credentials being decrypted.
- The Compose file publishes 5678 on host interfaces. Restrict EC2 security groups and host firewalls before starting it; add a TLS reverse proxy for ongoing use.
- Ollama has no host port published; n8n uses `http://ollama:11434` inside the Compose network. Do not add an unrestricted public 11434 mapping.
- `latest` image tags reproduce the requested baseline rather than a fixed original version. Pin tested versions/digests, review updates and verify restore procedures.
- The lab's `GroupMember.ReadWrite.All` permission is unnecessary for the exported calls. AD group changes are performed at their source of authority.

## Failure and replay behavior

| Failure point | Possible remaining state | Operator action / future control |
|---|---|---|
| AD membership removal fails | Account may remain enabled; no event is sent | Investigate delegated rights and membership, then retry deliberately |
| Account disablement fails after removal | Group membership is removed but account may remain enabled | Inspect AD and complete the disablement; do not report global success |
| POST fails after AD changes | Account disabled and group removed; n8n delivery uncertain | Check n8n executions; reconcile/replay without assuming no delivery |
| Graph lookup/revocation errors | AD changes remain; later branches may not execute | Alert and retry safely after resolving identity/permission/API issues |
| Graph returns a false result | No explicit false-result branch in this export | Public messages show the result; implement a deterministic failure gate and escalation |
| Slack/Sheets/SMTP/model failure | Other upstream operations may already have succeeded | Track each result; isolate/report failures rather than rerunning everything blindly |
| Cloud Sync/SCIM delay or failure | Cloud/AWS entitlements may not yet reflect AD | Inspect provisioning logs and target memberships; reconcile until confirmed |
| Duplicate invocation/event | Repeated revocation, duplicate rows/messages and a new run timestamp | Introduce a durable event ID, deduplication and original-event timestamps |

The PowerShell script supports `-WhatIf` and confirmation, but does not implement a transaction, rollback, outbox or automatic retry. A replay for an already-disabled user records the current run's disabled-state assertion in `disabledAt`, not the historical time of first disablement.

The lab payload does not carry independent AD result flags. n8n trusts that the authorized source executed the script correctly. Directly POSTing an arbitrary payload can trigger revocation without proving AD was changed. Add source authentication, target allowlists and authoritative verification before broader use.

Google Sheets appends are neither immutable nor deduplicated. Validate and safely handle fields before writing them to spreadsheets, including protection against formula interpretation. Move security audit events into a controlled SIEM/event store for production.

## Session and entitlement limits

Account disablement, Entra session revocation, AWS group deprovisioning, AWS portal sessions and AWS role sessions are different controls. This workflow invokes Graph's Entra revocation API only. It does not call an AWS session-control API.

Existing AWS credentials may remain usable subject to their AWS-side validity and policies. Investigate [AWS revocation guidance](https://docs.aws.amazon.com/singlesignon/latest/userguide/revoke-user-permissions.html) when active-session interruption is required. Removing one group does not rule out access from other groups, direct account assignments, other applications or separately issued credentials.

Graph success does not confirm synchronization completion. See the [Microsoft API reference](https://learn.microsoft.com/en-us/graph/api/user-revokesigninsessions?view=graph-rest-1.0) for Entra token/cookie behavior and possible delay.

## AI boundary

Ollama has no tools for Graph, AD or AWS. Its sole role is to summarize the record. The public prompt asks it to treat field values as data, preserve the Graph result, distinguish source-reported AD state from independently verified facts, and avoid claiming that AWS sessions ended.

Prompt instructions are not a guarantee against hallucination or prompt injection. Preserve structured API responses as evidence, use deterministic messages for critical outcomes, and never connect model output to entitlement changes or approvals. The public Slack alert is deterministic and separate from the model branch.

## Screenshot review and privacy inventory

All 30 source PNGs were visually reviewed. No unmasked password, client secret, SCIM bearer token, Slack token, SMTP/app password, Google OAuth secret, private key or n8n encryption key was found. Figure 05 contains a **masked** secret-token input. The “Access keys” links in portal images do not display key values.

The images are published unchanged to preserve implementation evidence. The following visible non-secret metadata is flagged because much of it is unnecessary for explaining the design. Code, sample payloads and the workflow use placeholders instead.

| Screenshot numbers after normalization | Visible metadata |
|---|---|
| 01–10 | AWS account/instance identifiers and federation URLs; Entra tenant/admin display identifiers; group/application object identifiers; personal email in 10 |
| 11–16 | Remote desktop public IP, domain/host information; Entra tenant/user identifiers; AWS identifiers and personal email in portal evidence |
| 18 | Ubuntu username and private host address |
| 19–21 | Remote desktop public IP, app/tenant identifiers and test-user UPN |
| 23–25 | Entra tenant/admin/group/user identifiers; remote desktop public IP in 24–25 |
| 26–29 | Test-user UPN and identity data; Entra user ID and workflow ID in mapping output; spreadsheet ID/public IP/profile imagery in 28; sender email/profile imagery in 29 |
| 17, 22, 30 | Workflow/node names, execution details or non-secret session/UI metadata |

These identifiers are not credentials, but can expose environment relationships and contact information. No exact values are duplicated into this inventory. The original ZIP, raw workflow export and pasted private instructions are not committed.

### Evidence corrections

- Figures 06–10 concern the initial **cloud-only** `AWS-Lab-Users` group. The final hybrid flow uses the separate AD-sourced `SG-AWS-Lab-Users` group.
- Figure 04 is the AWS identity-provider change **review screen**, not proof of an AD two-way domain trust.
- Figure 12 shows Cloud Sync **Disabled** during setup; Figure 13 proves successful **on-demand** creation. The README does not convert that into a screenshot-backed claim of continuous scheduler health.
- Figure 22 proves a Graph session-revocation result, not an AD disable operation performed by n8n.
- Original `23-SG-AWS-Lab-Users membership_is_removed_from_entra.png` is now Figure 23, **Entra-Group-Search-No-Results**. Its broad search cannot prove the actual group's member list is empty.
- Original `23-SG-AWS-Lab-User_is_removed_from_AWS_Identity_Center.png` is now Figure 24, **Entra-SG-AWS-Lab-Users-Membership-Removed**. It visibly shows Entra, not AWS.
- AWS zero-members and successful downstream SCIM update results are reported in the supplied lab notes, but their post-offboarding console/log screenshots are absent from this ZIP. A follow-up evidence capture should show the actual AWS group Users tab and the corresponding successful provisioning entry.
- Figure 25 shows an Entra **account-locked** message. The notes identify it as a fresh AWS portal login attempt. This message alone neither proves the specific lock/disable cause nor the state of an existing AWS session.
- Screenshots come from multiple stages/runs. The final workflow image is useful topology evidence; separate Slack, Sheets and email captures establish their respective delivery results.

No image has been generated, redrawn or altered to supply missing implementation evidence. Duplicate source numbering was normalized into unique numbers 01–30.

## Validation scope for this repository version

Publication checks cover JSON/YAML structure, retained workflow connections, credential/reference removal, placeholder destinations, Markdown image/file targets, unique screenshot numbering, image-byte preservation, PowerShell review and secret-pattern checks.

This publishing environment has no Windows Active Directory module, PowerShell runtime or Docker daemon. Consequently the recreated PowerShell/Compose files and modified workflow have not been executed end-to-end here. Run controlled integration and failure-path tests in your own lab after configuring credentials. The screenshot-backed results belong to the original implementation.
