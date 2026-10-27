# Application Insights Web Tracking HTTP Module Causes 403 Forbidden Error
---

## 📋 Introduction & Overview

When host applications deployed on Azure App Service attempt to interact with Azure Blob Storage containers, outbound HTTP requests may fail unexpectedly with an `HTTP 403 Forbidden` response. 

This issue is caused by the **Application Insights Dependency Tracking HTTP Module** (`DependencyTrackingTelemetryModule`). By default, this module injects request correlation headers into outgoing HTTP traffic to track telemetry across services. However, because Azure Blob Storage relies on strict authentication signatures (such as Shared Access Signatures or Shared Key authorization), modifying headers **after** the request signature is computed causes Azure Storage to reject the request as unauthorized.

This document details the affected infrastructure, error log diagnostics, root cause explanation, and the configuration steps required to resolve the issue without disabling overall Application Insights telemetry.

---

## 📌 Affected Azure Resources

| Resource Type | Resource Name | Purpose / Function |
| :--- | :--- | :--- |
| **Staging App Services** | `masked` | Staging web application hosts |
| **Storage Account** | `masked` | Target storage account hosting candidate documents |
| **Target Container** | `masked` | Destination blob container for uploaded files |

---

## 🚨 Diagnostics & Error Logs

The failure occurs during file upload operations within the application workflow.

### Application Error Logs

```text
2020-08-26T07:17:22 PID[2360] Error 5108 07:17:22 ERROR exception from InitializeContainer: The remote server returned an error: (403) Forbidden.
2020-08-26T07:17:22 PID[2360] Information 5108 07:17:22 INFO Candidate Profile Name /61dd00a4-5da5-4dfc-8b92-a69ef036a7a6.docx||Prod_emailbackup (1).docx?26/08/2020 07:17:22
2020-08-26T07:17:22 PID[2360] Error 5108 07:17:22 ERROR UploadFileToAzure exception: The remote server returned an error: (403) Forbidden.
```

### Request Flow & Failure Sequence

1. **User Action:** App initiates file upload via `POST` request to:
   `https://masked/api/sitecore/candidateresumes/uploadfiles`
2. **Outbound Call:** App Service attempts to write to Azure Storage:
   `https://masked.blob.core.windows.net:443/2020-hirecraft?restype=container`
3. **Response:** Azure Storage responds with `HTTP 403 Forbidden`.


---

## 🔍 Root Cause Analysis

The **Application Insights Web Tracking HTTP Module** attaches distributed tracing correlation headers (such as `Request-Id` or `traceparent`) to outbound HTTP traffic. 

When the Azure Storage SDK generates an authentication signature, it calculates the signature based on a snapshot of the HTTP request headers. If the Application Insights module injects additional correlation headers into the request **after** this signature generation step, the request received by `core.windows.net` fails signature verification, triggering an `HTTP 403 Forbidden` exception.

> 💡 **Tip:** For deeper insight into how dependency tracking works in ASP.NET application monitoring, refer to the [Microsoft Azure Monitor Dependency Tracking Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/app/asp-net-dependencies).

---

## 🛠️ Resolution Steps

To fix this issue, update `ApplicationInsights.config` to instruct the `DependencyTrackingTelemetryModule` to exclude domain-level correlation headers for outbound requests directed to Azure Storage endpoints (`core.windows.net`).

### Step-by-Step Fix Procedure

1. Navigate to the **Azure Portal** and open your **App Service**.
2. Under **Development Tools** in the left sidebar, click **App Service Editor (Preview)** and select **Go**.
3. In the file explorer, navigate to `wwwroot/ApplicationInsights.config`.
4. Locate the standard telemetry module block:

   ```xml
   <Add Type="Microsoft.ApplicationInsights.DependencyCollector.DependencyTrackingTelemetryModule, Microsoft.AI.DependencyCollector">
   </Add>
   ```

5. Replace it with the excluded domains configuration:

   ```xml
   <Add Type="Microsoft.ApplicationInsights.DependencyCollector.DependencyTrackingTelemetryModule, Microsoft.AI.DependencyCollector">
       <ExcludeComponentCorrelationHttpHeadersOnDomains>
           <Add>core.windows.net</Add>
       </ExcludeComponentCorrelationHttpHeadersOnDomains>
   </Add>
   ```

6. Save the file. 
7. Restart the App Service (**Stop** and then **Start**) to ensure the configuration changes take effect.

> ⚠️ **Important Note:** Excluding `core.windows.net` stops the injection of extra headers on requests to Azure Storage (preventing signature mismatch errors) while continuing to collect essential dependency performance telemetry across all other outbound services.

---

## 📚 References & Resources

* 🐙 **GitHub Issue Tracker:** [Azure SDK for .NET Issue #3460](https://github.com/Azure/azure-sdk-for-net/issues/3460)
* ❓ **Microsoft Q&A Thread:** [App Insights Dependency Tracking Caused 403 Error Solution](https://docs.microsoft.com/en-us/answers/questions/77707/app-insights-dependency-tracking-caused-http-403-f.html)
