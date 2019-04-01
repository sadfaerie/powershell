
####################################################################################
#   ESTABLISH AZURE CONNECTION
####################################################################################

$subscriptionProdId = "11111111-XXXXXXX"
$subscriptionProd = "Prod-Sub"

$subscriptionSandboxId = "2222222-YYYYYYY"
$subscriptionSanbox = "Sandbox-Sub"

$connectionName = "AzureRunAsConnection"
try {
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
} catch {
    if (!$servicePrincipalConnection) {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

####################################################################################
#   READ DATA FROM BLOB
####################################################################################

Get-AzureRmSubscription –SubscriptionName $subscriptionSanbox | Select-AzureRmSubscription

$resourceGroup = " "
$storageAccountName = " "
$containerName = " "
$prefix = " "

$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName
$storageAccountKey = (Get-AzureRmStorageAccountKey -Name $storageAccountName -ResourceGroupName $resourceGroup).Value[0]

$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
$blob = Get-AzureStorageBlob -Context $storageContext -Container $containerName -Prefix $prefix

$knownExpiredCerts = @() 

$blobContent = $blob.ICloudBlob.DownloadText()

$blobItems = (($blobContent -split ' ').Trim() | ForEach-Object { $_ }) 

foreach ($_ in $blobItems) {
    $knownExpiredCerts += $_
}
####################################################################################
#   ESTABLISH JIRA SESSION 
####################################################################################

$URI = "https://tools.hmcts.net/jira/"
$projectKey = "RDO"
$username = Get-AzureKeyVaultSecret -vaultName "rdo-atlassian-vault" -name "atlassian-service-account-username" 
$jirapass = Get-AzureKeyVaultSecret -vaultName "rdo-atlassian-vault" -name "atlassian-service-account-password" 

$auth = @{
username = $username.SecretValueText
password = $jirapass.SecretValueText
} | ConvertTo-Json -Depth 10

# create a session in JIRA in order to stay logged in and make changes
Invoke-RestMethod -uri "https://tools.hmcts.net/jira/rest/auth/latest/session" -ContentType "application/json" -Method POST -body $auth -SessionVariable mysession

####################################################################################
#   CHECK CERTIFICATES FOR EXPIRY DATE AND UPDATE BLOB 
####################################################################################

$minimumCertAgeDays = 30
Get-AzureRmSubscription –SubscriptionName $subscriptionProd | Select-AzureRmSubscription

$vaults = (Get-AzureRmKeyVault).VaultName
$updatedExpiredCerts = @()

foreach ($vault in $vaults) {
$certs = (Get-AzureKeyVaultCertificate -VaultName $vault)
    foreach ($cert in $certs) {
        $allCerts = (Get-AzureKeyVaultCertificate -VaultName $vault -Name $cert.Name)
        foreach ($item in $allCerts) {

        [datetime]$expires = $($cert.expires.date)
        [int]$certExpiresIn = ($expires - $(get-date)).Days

            if ($certExpiresIn -gt $minimumCertAgeDays) {

                if ($knownExpiredCerts.Contains($item.Thumbprint)) {
                    Write-Output "Certificate $($cert.Name) is no longer expired, removing."
                }

                else {
                    Write-Output "OK! $($cert.Name) expires in $($certExpiresIn) days."
                }

            }

            else {

                if ($knownExpiredCerts.Contains($item.Thumbprint)) {
                    Write-Output "Certificate $($cert.Name) is already known as expired, skipping."
                }

                else {
                    $subject = "WARNING! Certificate $($cert.Name) expires in $($certExpiresIn) days."
                    $description = "WARNING! $subscription : Certificate $($cert.Name) in Key Vault $vault expires in $($certExpiresIn) days."

# issuetype 10001 = story, no sub tasks, no parent issue | priority 1 = highest
 $global:IssueBody = 
@{
 fields = @{ 
 project = @{ key = $projectKey }
 summary = $subject
 description = $description 
 issuetype = @{ id = '10001' }
 priority = @{ id = '1' }
 }
 } | ConvertTo-Json -Depth 100

                    $IssueCreation = Invoke-WebRequest -uri "https://tools.hmcts.net/jira/rest/api/latest/issue/" -ContentType "application/json" -Method POST -Body $IssueBody -WebSession $mysession -UseBasicParsing | ConvertFrom-Json
                    $issueNumber = $IssueCreation.id

                }

                # Updated list of expired certificates
                $updatedExpiredCerts += $item.Thumbprint

            }
        } 
    } 
}

$temp = $updatedExpiredCerts 
$updatedExpiredCerts = ($temp | Sort-Object | Get-Unique)

$blob.ICloudBlob.UploadText($updatedExpiredCerts)
