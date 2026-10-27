# Send Test Email from Azure Web App to SendGrid via Kudu Console

## 📌 Introduction & Purpose

When troubleshooting email delivery failures reported by users in an Azure App Service environment, it is often necessary to isolate network connectivity, provider authentication, and credential validity from application-level bugs. 

This guide outlines two methods for manually triggering test emails directly from the **Azure Kudu PowerShell Console**:
1. **SMTP Authentication (`Send-MailMessage`):** Quick test using legacy SMTP credentials found in `web.config`.
2. **SendGrid REST API (Bearer Token):** A modern, highly secure method using API Keys and RESTful requests.

---

## 🛠️ Method 1: Testing via SMTP PowerShell Command

This method uses basic authentication with credentials retrieved directly from the App Service's configuration file.

### Step 1: Access Kudu Console

1. In the **Azure Portal**, navigate to the target **App Service**.
2. Under **Development Tools**, select **Advanced Tools** $\rightarrow$ click **Go**.
3. In the Kudu interface, open **Debug Console** $\rightarrow$ select **PowerShell**.

### Step 2: Retrieve SMTP Credentials

1. Open **App Service Editor (Preview)** from the Azure Portal (or navigate via Kudu file explorer).
2. Open `wwwroot/web.config`.
3. Locate the `<mailSettings>` section to copy the `userName`, `password`, `host`, and `port`:

```xml
<mailSettings>
    <smtp from="noreply@horizontal.com">
        <network host="smtp.sendgrid.net" password="xxxxxxxxxx" userName="xxxxxxxxxxxxxxx" port="587" />
    </smtp>
</mailSettings>
```

### Step 3: Execute PowerShell Script

Run the following commands sequentially in the Kudu PowerShell terminal:

```powershell
$User = "<enter_username_here>"
$PWord = ConvertTo-SecureString -String "<enter_password_here>" -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord

Send-MailMessage -To "your_email@masked.com" `
                 -From "noreply@masked.com" `
                 -Subject "Testing mail func 01" `
                 -Body "Hello World" `
                 -Credential $Credential `
                 -SmtpServer "smtp.sendgrid.net" `
                 -Port 587
```

> 💡 **Tip:** If the execution completes without returning an error message, the SMTP handshaking and outbound connection were successful.

### Step 4: Verify Delivery in SendGrid Portal

1. Log in to the [SendGrid Dashboard](https://app.sendgrid.com) using the credentials from `web.config`.
2. Navigate to **Activity** in the left navigation sidebar.
3. Search for the **To** address used in your test script to verify delivery status or review drop/bounce diagnostic logs.

---

## 🔒 Method 2: Testing via SendGrid REST API (Recommended)

Using API Bearer Token authentication bypasses SMTP restrictions and aligns with modern security practices.

> ⚠️ **Note:** The script below is specifically formatted for SendGrid v3 REST API. To use other providers (e.g., Mailgun, Postmark), update the `Uri` endpoint and API request payload according to their documentation.

### PowerShell API Script

```powershell
# Send test email via SendGrid REST API (v3)
# Credits: Paolo Frigo (https://www.scriptinglibrary.com)

function Send-EmailWithSendGrid {
    Param
    (
        [Parameter(Mandatory=$true)]
        [string] $From,
 
        [Parameter(Mandatory=$true)]
        [string] $To,
 
        [Parameter(Mandatory=$true)]
        [string] $ApiKey,
 
        [Parameter(Mandatory=$true)]
        [string] $Subject,
 
        [Parameter(Mandatory=$true)]
        [string] $Body
    )
 
    $headers = @{}
    $headers.Add("Authorization","Bearer $ApiKey")
    $headers.Add("Content-Type", "application/json")
 
    $jsonRequest = [ordered]@{
        personalizations = @(
            @{
                to = @(@{email = "$To"})
                subject = "$Subject" 
            }
        )
        from = @{email = "$From"}
        content = @( 
            @{ 
                type = "text/plain"
                value = "$Body" 
            }
        )
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri "https://api.sendgrid.com/v3/mail/send" -Method Post -Headers $headers -Body $jsonRequest 
}

# --- Execution ---
$From = "noreply@masked.com"
$To = "target_user@masked.com"
# Obtain API key from Azure Portal > SendGrid Account > Manage > API Keys
$APIKEY = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
$Subject = "TEST - SendGrid API"
$Body = "SENDGRID123"

Send-EmailWithSendGrid -From $From -To $To -ApiKey $APIKEY -Body $Body -Subject $Subject
```

> 🔑 **How to Obtain SendGrid API Key:**
> 1. Go to **Azure Portal** $\rightarrow$ **SendGrid Accounts** $\rightarrow$ select your instance.
> 2. Click **Manage** to open the SendGrid administrative portal.
> 3. Go to **Settings** $\rightarrow$ **API Keys** to generate or retrieve an active key.
