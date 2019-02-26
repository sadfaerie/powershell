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

$vaults = (Get-AzureRmKeyVault).VaultName

foreach ($vault in $vaults) {
$certs = (Get-AzureKeyVaultCertificate -VaultName $vault)

    foreach ($cert in $certs) {
        $allCerts = (Get-AzureKeyVaultCertificate -VaultName $vault -Name $cert.Name)
        
        foreach ($item in $allCerts) {
            [datetime]$expires = $($item.expires.date)
            [int]$certExpiresIn = ($expires - $(get-date)).Days
            
            if ($certExpiresIn -gt $minimumCertAgeDays) {
                Write-Output "OK! $($cert.Name) expires in $($certExpiresIn) days"
                }
            else {

                Write-Output "WARNING! $($cert.Name) expires in $($certExpiresIn) days."
                $description = "WARNING! $($cert.Name) expires in $($certExpiresIn) days."
                $subject = "WARNING! $($cert.Name) expires in $($certExpiresIn) days."

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
