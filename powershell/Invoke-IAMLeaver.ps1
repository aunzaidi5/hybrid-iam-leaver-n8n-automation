#Requires -Version 5.1
<#
.SYNOPSIS
Disables a lab AD user, removes direct AWS lab group membership and posts an event.
.DESCRIPTION
Sanitized implementation of the demonstrated lab logic, with preflight checks and
ShouldProcess support. Run only against an approved test identity. This is not a
transaction: production needs durable delivery, idempotency and reconciliation.
An HTTP acknowledgement does not mean Graph, notifications or SCIM have completed.
.EXAMPLE
.\Invoke-IAMLeaver.ps1 -SamAccountName 'jdoe' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SamAccountName,

    [string]$WebhookUrl = $env:N8N_LEAVER_WEBHOOK_URL,

    # Optional shared header; configure matching Header Auth on the n8n Webhook.
    [string]$WebhookToken = $env:N8N_LEAVER_WEBHOOK_TOKEN,

    [switch]$AllowInsecureHttp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$awsGroup = 'SG-AWS-Lab-Users'
$stage = 'preflight'
$adMutationAttempted = $false

try {
    if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
        throw 'Set N8N_LEAVER_WEBHOOK_URL or pass -WebhookUrl before running.'
    }
    $uri = $null
    if (-not [Uri]::TryCreate($WebhookUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http', 'https') -or $uri.UserInfo) {
        throw 'WebhookUrl must be an absolute HTTP(S) URL without embedded credentials.'
    }
    if ($uri.Scheme -eq 'http' -and -not $AllowInsecureHttp) {
        throw 'Use HTTPS; -AllowInsecureHttp is only for an isolated lab network.'
    }
    if ($uri.Scheme -eq 'http' -and -not [string]::IsNullOrWhiteSpace($WebhookToken)) {
        throw 'Do not send a webhook token over plaintext HTTP. Configure HTTPS.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
    $user = Get-ADUser -Identity $SamAccountName -Properties DisplayName, UserPrincipalName, Department, MemberOf, Enabled
    $group = Get-ADGroup -Identity $awsGroup
    if ([string]::IsNullOrWhiteSpace($user.UserPrincipalName)) {
        throw 'The AD user needs a synchronized UPN for Microsoft Graph lookup.'
    }
    Write-Host "Leaver found: $($user.SamAccountName)"

    if (-not $PSCmdlet.ShouldProcess($user.DistinguishedName,
        "Remove direct membership in $awsGroup, disable account and send leaver event")) {
        return
    }

    $stage = 'AD group membership removal'
    if ($user.MemberOf -contains $group.DistinguishedName) {
        $adMutationAttempted = $true
        Remove-ADGroupMember -Identity $group -Members $user -Confirm:$false
        Write-Host "Removed direct membership in $awsGroup."
    } else {
        Write-Host "Direct membership in $awsGroup is already absent."
    }

    $stage = 'AD account disablement'
    if ($user.Enabled) {
        $adMutationAttempted = $true
        Disable-ADAccount -Identity $user -Confirm:$false
        Write-Host "Disabled AD account: $SamAccountName"
    } else {
        Write-Host "AD account is already disabled: $SamAccountName"
    }

    # Timestamp records this run's assertion of disabled state, not a historical
    # disablement time when replaying an event for an already-disabled account.
    $payload = [ordered]@{
        samAccountName = $user.SamAccountName
        displayName = $user.DisplayName
        userPrincipalName = $user.UserPrincipalName
        department = $user.Department
        disabledAt = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 3

    $stage = 'webhook delivery'
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($WebhookToken)) {
        $headers['X-IAM-Webhook-Token'] = $WebhookToken
    }
    $null = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 30
    Write-Host 'Leaver event accepted by webhook. Check n8n execution and downstream provisioning separately.'
} catch {
    # Avoid logging URLs, tokens, response bodies or raw exceptions containing them.
    Write-Warning "Leaver processing failed during: $stage. Error type: $($_.Exception.GetType().Name)."
    if ($stage -eq 'webhook delivery') {
        Write-Warning 'AD changes completed, but webhook delivery is unconfirmed. Check n8n before replay to avoid duplicate notifications.'
    } elseif ($adMutationAttempted) {
        Write-Warning 'AD changes may be partially applied. Inspect account and group state before retrying.'
    } else {
        Write-Warning 'No AD mutation was attempted. Check URL configuration, identity, module and permissions.'
    }
    throw "Leaver processing failed at stage: $stage. Reconcile state before retrying."
}
