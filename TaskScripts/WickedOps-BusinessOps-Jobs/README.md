# WickedOps BusinessOps Jobs

Installs the six remaining jobs for the existing `C:\WickedAdmin\BusinessOps` scheduler framework.

## Jobs

- Daily Sales and Outreach Report: summarizes the last 24 hours of BusinessOps logs.
- Outreach Deliverability Watch: checks Gmail for bounces, complaints, and opt-outs.
- Weekly SEO and Indexing Report: reads Search Console query metrics for all three products.
- Prospect Follow-Up Queue: creates a review-only queue; it never sends email.
- Weekly Product Activity Report: summarizes public GitHub activity.
- Backup and Recovery Validation: creates and checksum-validates a local configuration backup.

## Install

Run PowerShell 7 as Administrator:

```powershell
.\Install-WickedOpsBusinessJobs.ps1
```

The daily report, product activity, and backup jobs work immediately. Gmail and Search Console jobs require a Google OAuth desktop client and a refresh token with these scopes:

- `https://www.googleapis.com/auth/gmail.readonly`
- `https://www.googleapis.com/auth/webmasters.readonly`

Store those values with:

```powershell
& 'C:\WickedAdmin\BusinessOps\Jobs\Set-WickedOpsBusinessSecrets.ps1'
```

Secrets are protected with Windows DPAPI LocalMachine and restricted by ACL to SYSTEM, Administrators, and read-only access for `WickedOpsSvc`.

Generated runtime folders (`Logs`, `Reports`, `Backups`, `Secrets`, and `State`) belong under `C:\WickedAdmin\BusinessOps` and must never be committed.
