# SSL Certificate Expiry Monitoring Solution

| Attribute | Details |
| :--- | :--- |
| **Author** | Pranesh Sathyanarayan |
| **Team** | Masked |
| **Platform** | Azure Serverless (PaaS - Timer Trigger) |
| **Target Email** | `masked` |

---

## 📌 Overview & Purpose

This solution provides automated monitoring and reporting for SSL/TLS certificate expiration dates across all publicly accessible web domains managed for Managed Services clients. 

The monitoring is executed on a scheduled basis via a serverless **Azure Functions (Timer Trigger)** setup. If any certificate is found to be expiring within the defined warning threshold (**60 days by default**), an automated HTML report is dispatched via SendGrid to the infrastructure operations team.

---

## ☁️ Azure Resource Metadata

| Configuration Property | Resource Value / Detail |
| :--- | :--- |
| **Azure Subscription** | `Masked` |
| **Resource Group** | `SSLCertificateMonitor` |
| **Function App Name** | `hztlcertmonitor` |
| **Storage Account** | `sslcertificatemonitb84b` |
| **Storage Share Quota** | 1 GB File Share |
---

## 📁 File Structure & Component Overview

The Timer Trigger function resides under `site/wwwroot/TimerTriggerforSSLexpiry/` inside the Azure Storage File Share:

```text
TimerTriggerforSSLexpiry/
├── run.ps1                   # Main PowerShell script (Execution logic & email rendering)
├── function.json             # Function definition & NCRONTAB schedule configuration
├── URL loader list.txt       # Master list of client domains to monitor
└── ExecutionLog.txt          # File log for tracking execution runs and runtime errors
```

---

## ⚙️ Managed Files & Configuration

### 1. Master URL Feed (`URL loader list.txt`)

> **Location:** `sslcertificatemonitb84b` > **File share** > `site/wwwroot/TimerTriggerforSSLexpiry/URL loader list.txt`

This file contains the list of target domain names to inspect during each execution.

#### Rules for Updating:
* **Segregation:** Entries are organized by client name using `###` headers (e.g., `### CLIENT1`).
* **Commenting Out Entries:** Any line matching or starting with `^###` or `#` is ignored by the parser script.
* **Adding New Sites:** Simply insert the raw domain or hostname on a new line without any `#` prefix.

```text
### client1
masked1.com
masked2.com

### client2
masked3.com
masked4.com
```

---

### 2. Schedule Configuration (`function.json`)

> **Location:** `sslcertificatemonitb84b` > **File share** > `site/wwwroot/TimerTriggerforSSLexpiry/function.json`

The execution schedule uses standard **NCRONTAB** expressions configured in the function binding:

```json
{
  "bindings": [
    {
      "name": "Timer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 0 8 * * MON"
    }
  ]
}
```

> 💡 **Schedule Note:** `"0 0 8 * * MON"` triggers the function every **Monday at 08:00 AM UTC**.

---

### 3. Execution Logging (`ExecutionLog.txt`)

> **Location:** `sslcertificatemonitb84b` > **File share** > `site/wwwroot/TimerTriggerforSSLexpiry/ExecutionLog.txt`

Logs all operation details, connection timeouts, TLS handshake failures, or network status errors during script execution.

> 💡 **Troubleshooting Tip:** If automated weekly emails are missing, inspect `ExecutionLog.txt` to verify if connection timeouts or invalid hosts halted the function run.

---

## 📧 Notifications & Configuration

| Parameter | Current Value / Settings |
| :--- | :--- |
| **Recipient Email (`$To`)** | `masked@masked.com` |
| **Sender Email (`$From`)** | `no-reply@masked.com` |
| **SendGrid API Key** | Loaded dynamically from App Settings: `$env:SENDGRID_API_KEY` |
| **Expiration Warning Threshold** | 60 days (`$ExpirationDays = 60`) |
| **TCP Timeout Limit** | 40 seconds (`$timeoutMs = 40000`) |

---

## 💻 Script Architecture & Source Code (`run.ps1`)

Below is the complete PowerShell script executed by the Timer Trigger. It reads the target domain list, initiates direct TCP/SSL stream handshakes to inspect certificate validity, and renders a responsive HTML email report sent via SendGrid REST API.

```powershell
# Input bindings are passed in via param block.
param($Timer)

# 1. Resolve relative paths using $PSScriptRoot (Azure Function execution root)
$scriptPath = $PSScriptRoot
$sitesFile  = Join-Path -Path $scriptPath -ChildPath "URL loader list.txt"

if (Test-Path $sitesFile) {
    $sites = Get-Content $sitesFile
} else {
    Write-Error "Site list file not found at: $sitesFile"
    return
}

$validsites = $sites | Where-Object { $_ -and $_ -notmatch '^###' }

$ExpirationDays = 60
$timeoutMs      = 40000

# 2. Fetch SendGrid API Key from Azure Function App Settings (Environment Variable)
$APIKEY = $env:SENDGRID_API_KEY
$From   = "no-reply@masked.com"
$To     = "masked@masked.com"

function Send-EmailWithSendGrid {
    param (
        [Parameter(Mandatory=$true)][string] $From,
        [Parameter(Mandatory=$true)][string] $To,
        [Parameter(Mandatory=$true)][string] $ApiKey,
        [Parameter(Mandatory=$true)][string] $Subject,
        [Parameter(Mandatory=$true)][string] $Body
    )
 
    $headers = @{
        "Authorization" = "Bearer $ApiKey"
        "Content-Type"  = "application/json"
    }
 
    $jsonRequest = [ordered]@{
        personalizations = @(
            @{
                to      = @(@{ email = $To })
                subject = $Subject
            }
        )
        from    = @{ email = $From }
        content = @(
            @{
                type  = "text/html"
                value = $Body
            }
        )
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri "https://api.sendgrid.com/v3/mail/send" -Method Post -Headers $headers -Body $jsonRequest
}

# Initialize dynamic string holder
$tableRows = ""

# Loop through all valid domains
# any custom port can have the port value replaced as below
foreach ($i in $validsites) {
    $port = '443'
    if ($i -match 'masked-8984.com') {
        $port = '8984'
    }

    $certExpiresIn  = $null
    $expirationDate = $null
    $certname       = $null
    $thumbprint     = $null
    $issuer         = $null

    try {
        $request = [System.Net.Sockets.TcpClient]::new($i, $port)
        $stream  = [System.Net.Security.SslStream]::new($request.GetStream())
        $stream.AuthenticateAsClient($i)
        
        $certname       = $stream.RemoteCertificate.Subject
        $issuer         = $stream.RemoteCertificate.Issuer
        $thumbprint     = $stream.RemoteCertificate.Thumbprint
        $effectiveDate  = $stream.RemoteCertificate.GetEffectiveDateString() -as [datetime]
        $expirationDate = $stream.RemoteCertificate.GetExpirationDateString() -as [datetime]

        [int]$certExpiresIn = (New-TimeSpan -Start (Get-Date) -End $expirationDate).Days
        
        Write-Output "Checked $i - Expires in: $certExpiresIn days"
    }
    catch {
        Write-Warning "URL check error for ${i}: $_"
        continue
    }

    # If certificate expires within threshold, append table row
    if ($null -ne $certExpiresIn -and $certExpiresIn -le $ExpirationDays -and $certExpiresIn -ge 0) {
        $tableRows += @"
<tr>
    <td style="padding: 8px 10px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 13px; color: #323130; border-bottom: 1px solid #E1DFDD;">$certExpiresIn days</td>
    <td style="padding: 8px 10px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 13px; color: #323130; border-bottom: 1px solid #E1DFDD;">$i</td>
    <td style="padding: 8px 10px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 13px; color: #323130; font-weight: bold; border-bottom: 1px solid #E1DFDD;">$certname</td>
    <td style="padding: 8px 10px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 13px; color: #323130; border-bottom: 1px solid #E1DFDD;">$($expirationDate.ToString('dd/MM/yyyy HH:mm'))</td>
    <td style="padding: 8px 10px; font-family: Consolas, 'Courier New', monospace; font-size: 11px; color: #605E5C; border-bottom: 1px solid #E1DFDD;">$thumbprint</td>
    <td style="padding: 8px 10px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 13px; color: #323130; border-bottom: 1px solid #E1DFDD;">$issuer</td>
</tr>
"@
    }
}

# --- Construct Email Output (After processing all domains) ---
$dateforsubject = Get-Date -Format "dd/MM/yyyy"
$messagetitle   = "Weekly Certificate Status report for $dateforsubject"

$headerhtml = @"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=us-ascii" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <!--[if gte mso 9]>
    <xml>
      <o:OfficeDocumentSettings>
        <o:AllowPNG/>
        <o:PixelsPerInch>96</o:PixelsPerInch>
      </o:OfficeDocumentSettings>
    </xml>
    <![endif]-->
</head>
<body style="margin: 0; padding: 0; background-color: #F3F2F1; font-family: 'Segoe UI', Arial, sans-serif;">
    <table border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #F3F2F1; table-layout: fixed;">
        <tr>
            <td align="center" style="padding: 20px 10px;">
                <!--[if (gte mso 9)|(IE)]>
                <table align="center" border="0" cellspacing="0" cellpadding="0" width="850">
                <tr>
                <td>
                <![endif]-->
                <table border="0" cellpadding="0" cellspacing="0" width="100%" style="max-width: 850px; background-color: #FFFFFF; border: 1px solid #EDEBE9;">
                    <tr>
                        <td style="background-color: #0078D4; padding: 18px 24px;">
                            <h2 style="margin: 0; color: #FFFFFF; font-family: 'Segoe UI', Arial, sans-serif; font-size: 20px; font-weight: bold;">
                                Weekly Certificate Status Report
                            </h2>
                            <p style="margin: 4px 0 0 0; color: #DEECF9; font-family: 'Segoe UI', Arial, sans-serif; font-size: 12px;">
                                Generated on $dateforsubject
                            </p>
                        </td>
                    </tr>
                    <tr>
                        <td style="padding: 24px;">
                            <table border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse: collapse; text-align: left;">
                                <thead>
                                    <tr style="background-color: #F3F2F1;">
                                        <th style="padding: 10px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 12px; font-weight: bold; color: #323130; border-bottom: 2px solid #0078D4; text-align: left;">Expiry</th>
                                        <th style="padding: 10px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 12px; font-weight: bold; color: #323130; border-bottom: 2px solid #0078D4; text-align: left;">Domain Checked</th>
                                        <th style="padding: 10px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 12px; font-weight: bold; color: #323130; border-bottom: 2px solid #0078D4; text-align: left;">Certificate Name</th>
                                        <th style="padding: 10px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 12px; font-weight: bold; color: #323130; border-bottom: 2px solid #0078D4; text-align: left;">Expiry Date (UTC)</th>
                                        <th style="padding: 10px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 12px; font-weight: bold; color: #323130; border-bottom: 2px solid #0078D4; text-align: left;">Thumbprint</th>
                                        <th style="padding: 10px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 12px; font-weight: bold; color: #323130; border-bottom: 2px solid #0078D4; text-align: left;">Issuer</th>
                                    </tr>
                                </thead>
                                <tbody>
"@

$footerhtml = @"
                                </tbody>
                            </table>
                            <br />
                            <table border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #FFF4CE;">
                                <tr>
                                    <td width="4" style="background-color: #FFB900;"></td>
                                    <td style="padding: 12px 16px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 12px; color: #323130; line-height: 1.4;">
                                        <strong>Note:</strong> If no certificates appear above, there are no SSL/TLS certificates expiring within 60 days.
                                    </td>
                                </tr>
                            </table>
                            <br />
                            <table border="0" cellpadding="0" cellspacing="0" width="100%" style="border-top: 1px solid #EDEBE9;">
                                <tr>
                                    <td style="padding-top: 12px; font-family: 'Segoe UI', Arial, sans-serif; font-size: 11px; color: #A19F9D; text-align: center;">
                                        Email and Certificate Monitoring Solution | Designed & Managed by <strong>Masked</strong>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>
                </table>
                <!--[if (gte mso 9)|(IE)]>
                </td>
                </tr>
                </table>
                <![endif]-->
            </td>
        </tr>
    </table>
</body>
</html>
"@

# Construct full body
$finalhtml = $headerhtml + $tableRows + $footerhtml

# Send email using SendGrid
if ($APIKEY) {
    Send-EmailWithSendGrid -From $From -To $To -ApiKey $APIKEY -Body $finalhtml -Subject $messagetitle
    Write-Output "Email successfully sent via SendGrid."
} else {
    Write-Error "SendGrid API key missing. Please set SENDGRID_API_KEY in App Settings."
}
```

---
## Author - Pranesh Sathyanarayan
### Published First : 27 Oct 2026
#### AI agent disclosure - no AI used to generate content, gemini AI was used only to perform markdown formatting and beautification.

#### "This work is dedicated to the public domain under CC0 1.0 Universal. You are free to copy, modify, distribute, and perform the work, even for commercial purposes, all without asking permission."
