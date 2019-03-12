# JIRA / Confluence vars
$URI = "http:// #### "
$PAGEID = " #### "
$PAGEKEY = " #### "
$PAGETITLE = " Azure Key Vault Certificates "
$VER = "$URI/rest/api/content/$PAGEID"+"?expand=version"
$UPDATE = "$URI/rest/api/content/$PAGEID"
$ProjectKey = " #### "

# Authorisation header for Confluence Invoke-RestMethod
$user = " #### "
$pass = " #### "
$creds = "${user}:${pass}"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($creds)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"
$header = @{ Authorization = $basicAuthValue }



################################
# ESTABLISH RUNBOOK CONNECTION #
################################

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

###########################################################
# GET INFORMATION ABOUT CERTIFICATED STORED IN KEY VAULTS #
###########################################################

$sub = ""
Select-AzureRmSubscription $sub

$vaults = (Get-AzureRmKeyVault).VaultName
$tableItems = @()

foreach ($vault in $vaults) {
$certs = (Get-AzureKeyVaultCertificate -VaultName $vault)
    if($certs) {
    foreach ($cert in $certs) {
        $certPolicies = (Get-AzureKeyVaultCertificatePolicy -VaultName $vault -Name $cert.Name)

        $certArray = @()
        foreach ($policy in $certPolicies) {
            $certObj = $null
            $certObj = New-Object System.Object
            $certObj | Add-Member -type NoteProperty -Name Name -Value $cert.Name
            $certObj | Add-Member -type NoteProperty -Name VaultName -Value $cert.VaultName
            $certObj | Add-Member -type NoteProperty -Name Created -Value $cert.Created
            $certObj | Add-Member -type NoteProperty -Name Expires -Value $cert.Expires
            if($policy.Subject){
                $certObj | Add-Member -type NoteProperty -Name Subject -Value $cert.Certificate.Subject
            }
            else {
                $certObj | Add-Member -type NoteProperty -Name Subject -Value "N/A"
            }
            if($cert.Certificate.SubjectName){
                $certObj | Add-Member -type NoteProperty -Name SubjectName -Value $cert.Certificate.SubjectName
            }
            else {
                $certObj | Add-Member -type NoteProperty -Name SubjectName -Value "N/A"
            }
            if($policy.DnsNames){
                $certObj | Add-Member -type NoteProperty -Name DnsNames -Value $policy.DnsNames 
            }
            else {
                $certObj | Add-Member -type NoteProperty -Name DnsNames -Value "N/A"
            }
            if($policy.KeyUsage){
                $certObj | Add-Member -type NoteProperty -Name Usage -Value $policy.KeyUsage
            }
            else {
                $certObj | Add-Member -type NoteProperty -Name Usage -Value "N/A"
            }
            $certArray += $certObj        
        }

        foreach ($item in $certArray) 
        {
            $certName = $item | Select-Object -ExpandProperty Name
            $certVault = $item | Select-Object -ExpandProperty VaultName
            $certCreated = $item | Select-Object -ExpandProperty Created
            $certExpires = $item | Select-Object -ExpandProperty Expires
            $certSubject = $item | Select-Object -ExpandProperty Subject
            $certSubjectName = $item | Select-Object -ExpandProperty SubjectName
            $certDnsNames = $item | Select-Object -ExpandProperty DnsNames
            $certKeyUsage = $item | Select-Object -ExpandProperty Usage
        }

        $certItem = "<tr><td>$certName</td><td>$certVault</td><td>$certSubject</td><td>$certSubjectNam</td><td>$certDnsNames</td><td>$certKeyUsage</td><td>$certCreated</td><td>$certExpires</td></tr>"
        $tableItems += $certItem
        
        }
    }
}


##############################################
# GENERATE SIMPLE HTML OUTPUT FOR CONFLUENCE #
##############################################

[string]$tableHeader = "<table cellpadding='15' cellspacing='2'><tr><th bgcolor='#f2f2f2'>Subscription</th><th bgcolor='#f2f2f2'>Name</th><th bgcolor='#f2f2f2'>Resource Group</th><th bgcolor='#f2f2f2'>Thumbprint</th><th bgcolor='#f2f2f2'>Created on</th><th bgcolor='#f2f2f2'>Expires on</th></tr>"
[string]$tableFooter = "</table>"
[string]$table = $tableHeader + $tableItems + $tableFooter

# get page version (required by Confluence)
$obj = Invoke-RestMethod -Uri $VER -Headers $header -Method GET | Select-Object -ExpandProperty version | Select-Object number
$currentVersion = $obj.number
$incVersion = [int]$currentVersion +1

# Automation notification
$warn = "<h4><span style='color:red'>WARNING!</span> This page is generated automatically, any manual changes will get overwritten!</h4>"

# Generate Confluence page content
$pageContent = "$warn $table"
$pageContent
$body = @{
    id = $PAGEID
    type = "page"
    title = $PAGETITLE
    space = @{ 
        key = $PAGEKEY
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
    Invoke-RestMethod -Uri " ### insert-uri ### " -Headers $header -Method PUT -ContentType "application/json" -Body $body 
} 
catch { Write-Output $_.Exception  }


##################################################
# CHECK IF SERVICE PRINCIPAL ACCESSED ALL VAULTS #
##################################################

$vaults = (Get-AzureRmKeyVault).VaultName 
foreach ($vault in $vaults) { 
    try { 
    $allCerts = Get-AzureKeyVaultCertificate -VaultName $vault -ErrorAction Stop
    } 
    catch [Microsoft.Azure.KeyVault.Models.KeyVaultErrorException] { 
        $time=Get-Date 
        Write-Output "$time $SPName couldn't read $vault : $_"
        $subject = "Runbook couldn't read $vault"
        $description  = "Service Principal $SPName could not access Key Vault $vault due to $_ and was unable to update JIRA & Confluence with the certificate metadata. Please address the issue immediately."
    
        # create a session in JIRA in order to stay logged in and make changes
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
