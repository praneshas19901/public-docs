# Application Insights Web Tracking HTTP Module Causes 403 Forbidden Error

---

## 📌 Issue Overview

App Services (`cd0` and `cd1`) are failing to connect or upload files to Azure Storage Account containers (`webcanddoc`), resulting in an **HTTP 403 Forbidden** error.

### Affected Azure Resources

| Resource Type | Resource Name |
| :--- | :--- |
| **Staging App Services** | `cd0`, `cd1` |
| **Storage Account** | `masked` |
| **Target Blob Container** | `webcanddoc/2020-hirecraft` |

---

## 🚨 Diagnostics & Error Logs

The issue triggers when attempting to upload a file through the application interface.

### Error Stack Trace

```text
2020-08-26T07:17:22 PID[2360] Error 5108 07:17:22 ERROR exception from InitializeContainer: The remote server returned an error: (403) Forbidden.
2020-08-26T07:17:22 PID[2360] Information 5108 07:17:22 INFO Candidate Profile Name /61dd00a4-5da5-4dfc-8b92-a69ef036a7a6.docx||Prod_emailbackup (1).docx?26/08/2020 07:17:22
2020-08-26T07:17:22 PID[2360] Error 5108 07:17:22 ERROR UploadFileToAzure exception: The remote server returned an error: (403) Forbidden.
```

### Transaction Sequence

1. **Initiating Request:** `POST` request to `https://masked/api/sitecore/candidateresumes/uploadfiles`
2. **Target Destination:** `https://masked:443/2020-hirecraft?restype=container`
3. **Result:** Request fails with `HTTP 403 Forbidden`.


---

## 🔍 Root Cause Analysis

The **Application Insights Web Tracking HTTP Module** modifies outgoing HTTP headers for dependency tracking *after* the Azure Storage Shared Access Signature (SAS) or request authorization signature has already been calculated. Because the headers no longer match the generated signature, Azure Storage rejects the request with an `HTTP 403 Forbidden` response.

> 💡 **Tip:** To learn more about how dependency tracking functions in ASP.NET, consult the [Microsoft Azure Monitor Dependency Tracking Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/app/asp-net-dependencies).

---

## 🛠️ Resolution Steps

To resolve this error, configure Application Insights to exclude domain-level correlation headers for requests heading to Azure Storage endpoints (`core.windows.net`).

### Step-by-Step Fix

1. Open the **Azure Portal** and navigate to your **App Service**.
2. Under **Development Tools**, select **App Service Editor (Preview)** and click **Go**.
3. In the file explorer, locate and open `wwwroot/ApplicationInsights.config`.
4. Locate the following code block:

```xml
<Add Type="Microsoft.ApplicationInsights.DependencyCollector.DependencyTrackingTelemetryModule, Microsoft.AI.DependencyCollector">
</Add>
```

5. Replace it with:

```xml
<Add Type="Microsoft.ApplicationInsights.DependencyCollector.DependencyTrackingTelemetryModule, Microsoft.AI.DependencyCollector">
    <ExcludeComponentCorrelationHttpHeadersOnDomains>
        <Add>core.windows.net</Add>
    </ExcludeComponentCorrelationHttpHeadersOnDomains>
</Add>
```

6. Save the file, then **Stop** and **Start** (restart) the App Service for changes to take effect.

> ⚠️ **Important Note:** Excluding `core.windows.net` prevents telemetry headers from interfering with authentication signatures while maintaining standard dependency logging for other outbound services.

---

## 📚 References & Further Reading

* 🐙 **GitHub Issue Tracker:** [Azure SDK for .NET Issue #3460](https://github.com/Azure/azure-sdk-for-net/issues/3460)
* ❓ **Microsoft Q&A Thread:** [App Insights Dependency Tracking Caused 403 Error](https://docs.microsoft.com/en-us/answers/questions/77707/app-insights-dependency-tracking-caused-http-403-f.html)
