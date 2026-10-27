#interactive login to azure account
Connect-AzAccount
#put user name and password in the prompts, complete MFA if required


#copy paste the below function and load it into memory

#function starts

function Get-CertDetailsforWebApp
{

param (
        [string]$SubscriptionId,
        [string]$tenantId
    )

#set the context to subscription
Set-AzContext -Tenant $tenantId -Subscription $SubscriptionId

$Ct= Get-AzContext 
$Name = ($Ct.Subscription.Name)
$rg = Get-AzResourceGroup
$outdir = "C:\users\$env:UserName\$Name"
New-Item -Path $outdir -ItemType Directory -ErrorAction SilentlyContinue

foreach ($r in $rg.ResourceGroupName)
{
    try
    {
    Write-Host -ForegroundColor Green "Generating output for resource group $r"
    $c = Get-AzWebAppCertificate -ResourceGroupName $r
    $c | Select FriendlyName,ExpirationDate,Thumbprint | Export-Csv -Path $outdir\SSLDetsSummary_$r.csv
    Write-Host -ForegroundColor Green "Output saved at $outdir\SSLDetsSummary_$r.csv"

    try
    {
    Foreach ($i in $c)
    {
    $t=$i.Thumbprint
    $i.hostnames | Out-File "$outdir\Hostnames_$t.txt" -Append
    Write-Host -ForegroundColor Green "Thumbprint Hostnames saved at $outdir\Hostnames_$t.txt"
    }
    }
    catch
    {
    "Error Occured"
    $_
    }
    
    }
    catch
    {
    "Error Occured"
    $_
    }
}
Write-Host -ForegroundColor Green "All output files are saved at $outdir"
}

#Syntax:

#Get-CertDetailsforWebApp -SubscriptionId <enter subscription id> -tenantId <enter tenant id>

#Remove the comment # at the start of the line 68 and execute it afterwards by populating the desired values

#E.g.
#Get-CertDetailsforWebApp -SubscriptionId xxxxxxxxxxxxxxxxxxxx -tenantId xxxxxxxxxxxxxxxxxxxxxxx

#the csv files generated will gve you the expiry date of all certificates.
#to get the hostname details,check the specific file with thumbprint in the filename.

#Appendix - If you have repeating hostnames across different certificates, then run below line to get a single list of all unique hostnames
gc $outdir\*.txt | sort | get-unique > $outdir\Allhostnames_unique.txt
