$URI = "http://confluence"
$PROJECTKEY = "input-project-key"
$PAGEID = "input-page-id"
$PAGETITLE = "input-page-title"
$VER = "$URI/rest/api/content/$PAGEID"+"?expand=version"
$UPDATE = "$URI/rest/api/content/$PAGEID"

# generate authorisation header
$user = "input-jira-user"
$pass = "input-jira-user-password"
$creds = "${user}:${pass}"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($creds)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"
$header = @{ Authorization = $basicAuthValue }

$connectionName = "AzureRunAsConnection"
try {
    # Get the connection "AzureRunAsConnection"
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
} catch {
    if (!$servicePrincipalConnection) {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

$resourceGroups = Get-AzureRmResourceGroup
$tableItems = @()
if ($resourceGroups) 
{
foreach ($resourceGroup in $resourceGroups)
    {
    $resourceGroupName = "$($resourceGroup.ResourceGroupName)"
    $autoAccounts = Get-AzureRmAutomationAccount -ResourceGroupName $resourceGroupName      
    if ($autoAccounts)
        {
        $autoAccountName = "$($autoAccounts.AutomationAccountName)"
        $autoResourceGroup = "$($autoAccounts.ResourceGroupName)"
        $autoAccountCertificates = Get-AzureRmAutomationCertificate -ResourceGroupName $autoResourceGroup -AutomationAccountName $autoAccountName

        $certArray = @()
        foreach ($certificate in $autoAccountCertificates)
            {            
                $certObjSub = Get-AzureRmContext
                $certObj = $null
                $certObj = New-Object System.Object
                $certObj | Add-Member -type NoteProperty -Name Name -Value $certificate.Name
                $certObj | Add-Member -type NoteProperty -Name Subscription -Value $certObjSub.Subscription.Name
                $certObj | Add-Member -type NoteProperty -Name AutomationAccount -Value $certificate.AutomationAccountName
                $certObj | Add-Member -type NoteProperty -Name ResourceGroupName -Value $certificate.ResourceGroupName
                $certObj | Add-Member -type NoteProperty -Name Thumbprint -Value $certificate.Thumbprint
                $certObj | Add-Member -type NoteProperty -Name CreationTime -Value $certificate.CreationTime.Date
                $certObj | Add-Member -type NoteProperty -Name ExpiryTime -Value $certificate.ExpiryTime.Date
                $certArray += $certObj            
            }

        foreach ($item in $certArray) 
            {
                $certName = $item | Select-Object -ExpandProperty Name
                $certSub = $item | Select-Object -ExpandProperty Subscription
                $certRG = $item | Select-Object -ExpandProperty ResourceGroupName
                $certThumbprint = $item | Select-Object -ExpandProperty Thumbprint
                $certCreate = $item | Select-Object -ExpandProperty CreationTime
                $certExpire = $item | Select-Object -ExpandProperty ExpiryTime
                [string]$certItem = "<tr><td>$certSub</td><td>$certName</td><td>$certRG</td><td>$certThumbprint</td><td>$certCreate</td><td>$certExpire</td></tr>"
                $tableItems += $certItem
            }
        }
    }
    [string]$tableHeader = "<table cellpadding='15' cellspacing='2'><tr><th bgcolor='#f2f2f2'>Subscription</th><th bgcolor='#f2f2f2'>Name</th><th bgcolor='#f2f2f2'>Resource Group</th><th bgcolor='#f2f2f2'>Thumbprint</th><th bgcolor='#f2f2f2'>Created on</th><th bgcolor='#f2f2f2'>Expires on</th></tr>"
    [string]$tableFooter = "</table>"
    [string]$table = $tableHeader + $tableItems + $tableFooter
}

    # get page version
    try {
    $obj = Invoke-RestMethod -Uri $VER -Headers $header -Method GET | Select-Object -ExpandProperty version | Select-Object number
    }
    catch { Write-Output $_.Exception }
    
    $currentVersion = $obj.number
    $incVersion = [int]$currentVersion +1

    $warn = "<h4><span color='red'>WARNING!</span> This page is generated automatically, any manual changes will get overwritten!</h4>"

    $pageContent = "$warn $table"
    $pageContent
    $body = @{
        id = $PAGEID
        type = "page"
        title = $PAGETITLE
        space = @{ 
            key = $PROJECTKEY 
            }
        body = @{
            storage = @{
                value = $pageContent
                representation = "storage"
                }
            }
        version = @{ 
            number = $incVersion
            }
    } | ConvertTo-Json -Depth 100

    try { 
        Invoke-RestMethod -Uri $UPDATE -Headers $header -Method PUT -ContentType "application/json" -Body $body 
    } 
    catch { Write-Output $_.Exception }
