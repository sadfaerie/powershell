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

$currentSubscription = (Get-AzureRmContext).Subscription
$resourceGroups = Get-AzureRmResourceGroup
if ($resourceGroups) 
{
    foreach ($ResourceGroup in $resourceGroups)
     {
        $ResourceGroupName = "$($ResourceGroup.ResourceGroupName)"
        $allCertificates = Get-AzureRmWebAppCertificate -ResourceGroupName $ResourceGroupName

           foreach ($certificate in $allCertificates)
            {
                $certSubjects = $($certificate.SubjectName).replace(',', '`n')
                $certSubject = $($certificate.SubjectName).split(',')[0]
                [datetime]$expiration = $($certificate.ExpirationDate)
                [int]$certExpiresIn = ($expiration - $(get-date)).Days

                if ($certExpiresIn -gt $minimumCertAgeDays)
                    {
                        Write-Output "OK! Certificate for $certSubject expiry date is $($certificate.ExpirationDate)"
                        Write-Output "OK! This certificate expires in $certExpiresIn days [on $expiration] `n" 
                    }
                else
                    {

                        Write-Output "WARNING: Certificate for $certSubject expires in $certExpiresIn days [on $expiration] `
                        This certificate can be found in resourcegroup: $($ResourceGroup.ResourceGroupName) in $($currentSubscription.Name)`
                        SubjectNames: $certSubjects"
                        $description = "WARNING: Certificate for $certSubject expires in $certExpiresIn days [on $expiration] `
                        This certificate can be found in resourcegroup: $($ResourceGroup.ResourceGroupName) in $($currentSubscription.Name) `
                        SubjectNames: $certSubjects"

                        $subject =  "WARNING: Web App Certificate for $certSubject expires in $certExpiresIn days"


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
}

else
{
    Write-Output "Couldn't find any resource groups within $($currentSubscription.Name) subscription."
}