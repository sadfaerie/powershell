# This script has originally been created by Bram Stoop https://bramstoop.com/, and modified by karanotts 

Param(
[Parameter(Mandatory = $false)]
[string] $minimumCertAgeDays = 30
)

$URI = "input-JIRA-URI"
$ProjectKey = "input-project-key"
$global:username = "input-username"
$global:jirapass = (Get-AzureKeyVaultSecret -vaultName "input-vault-name" -name "input-secret-name").SecretValueText 

$auth = @{
 username = $username
 password = $jirapass
 } | ConvertTo-Json -Depth 10

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
            foreach ($certificate in $autoAccountCertificates)
            {
            [datetime]$expiration = $($certificate.ExpiryTime.Date)
            [int]$certExpiresIn = ($expiration - $(get-date)).Days
                if ($certExpiresIn -gt $minimumCertAgeDays)
                {
                    Write-Output "OK! $($certificate.Name) in $($certificate.AutomationAccountName) expiry date is $($certificate.ExpiryTime.Date)" 
                }
                else
                {
                Write-Output "WARNING! $($certificate.Name) in $($certificate.AutomationAccountName) expires on $($certificate.ExpiryTime.Date)" 
                $description = "WARNING! Certificate $($certificate.Name) in for Automation Account $($certificate.AutomationAccountName) expires in $certExpiresIn days on $($certificate.ExpiryTime.Date)"                      
                $subject =  "WARNING: Automation Account Certificate for $($certificate.AutomationAccountName) expires in $certExpiresIn days"
                
                #create a session in JIRA in order to stay logged in and make changes
                Invoke-RestMethod -uri "$URI/rest/auth/latest/session" -ContentType "application/json" -Method POST -body $auth -SessionVariable mysession

                $global:IssueCreationBody = 
                @{
                fields = @{
                project = @{ key = $projectKey }
                summary = $subject
                description = $description 
                issuetype = @{ id = '10003'  }
                # assignee = @{ name = $username }
                priority = @{ id = '1'  }
                }
                } | ConvertTo-Json -Depth 100

                $IssueCreation = Invoke-WebRequest -uri "$URI/rest/api/latest/issue/" `
                -ContentType "application/json" -Method POST -Body $IssueCreationBody -WebSession $mysession -UseBasicParsing | ConvertFrom-Json
                $issueNumber = $IssueCreation.id

                }
            }
        }
    else
        { 
            Write-Output "Couldn't find any automation accounts in $resourceGroupName in $($subscriptions.Name) subscription."
        }
    }
}
        