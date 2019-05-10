

# Dados de acesso ao Zabbix
[String] $ZBX_URL  = 'http://<URL do ZABBIX Server>/zabbix/api_jsonrpc.php'
[String] $ZBX_User = '<Zabbix API User>'
[String] $ZBX_Pass = '<Zabbix API Pass>'
[String] $ZBX_AUTHToken = ''
   [Int] $ZBX_AUTHID = 0
   [Int] $ZBX_DELAY = 600


# Conecta no Azure
$connectionName = "AzureRunAsConnection" 
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    $LoginOK = Login-AzureRmAccount -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}


Function WRequest ([String]$content = "") {

    try
    {
        $WebRequest = [System.Net.HttpWebRequest]::Create($ZBX_URL)
        $encodedContent = [System.Text.Encoding]::UTF8.GetBytes($content)
        $WebRequest.Method = 'Post'    
        $WebRequest.ContentType = "application/json"

        # Verificando se tem dado para o post
        if($encodedContent.length -gt 0) {
            $webRequest.ContentLength = $encodedContent.length
            $requestStream = $webRequest.GetRequestStream()
            $requestStream.Write($encodedContent, 0, $encodedContent.length)
            $requestStream.Close()
        }

        [System.Net.WebResponse] $resp = $webRequest.GetResponse();
        if($resp -ne $null) 
        {
            $rs = $resp.GetResponseStream();
            [System.IO.StreamReader] $sr = New-Object System.IO.StreamReader -argumentList $rs;
            [string] $results = $sr.ReadToEnd();

            return $results
        }
        else
        {
            Write-Output "Result empty"
        }
    }
    catch
    {        
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}


Function ZBX_Conecta {

    $request =  @{
        "jsonrpc"= "2.0"
        "method"= "user.login"
        "params"= @{
            "user"= $ZBX_User
            "password"= $ZBX_Pass
        }
        "id"= 1
        "auth"= $null
    } | ConvertTo-Json

    WRequest($request)

}

Function ZBX_auth {
    $AUTH = ZBX_Conecta # | ConvertFrom-Json    
    $AR_AUTH = ConvertFrom-Json –InputObject $AUTH
     
    $global:ZBX_AUTHToken = $AR_AUTH[0].result
    $global:ZBX_AUTHID = 1
}

Function List_hosts {
    $request =  @{
        "jsonrpc"= "2.0"
        "method"= "host.get"
        "params"= @{
            "output" = @("hostid", "name", "status")
        }
        "id"= ++$Global:ZBX_AUTHID
        "auth"= $ZBX_AUTHToken
    } | ConvertTo-Json

    WRequest($request)
}

Function StatusMonitoramento([String]$HostID = "", [Int]$Status = 0) {
    $request =  @{
        "jsonrpc"= "2.0"
        "method"= "host.update"
        "params"= @{
            "hostid" = "$HostID"
            "status" = "$Status"
        }
        "id"= ++$Global:ZBX_AUTHID
        "auth"= $ZBX_AUTHToken
    } | ConvertTo-Json

    WRequest($request)
}

# conectando no Zabbix
ZBX_auth

# Lista os hosts
$dados = List_hosts

# Converte os dados  em array
$ardados = ConvertFrom-Json –InputObject $dados

# Lista de VMs no Zabbix
$ZBX_VMs = $ardados.result 

# Coletando as VMs taggeadas.
[array]$VMs = Get-AzureRmVM -Status | Where-Object {$PSItem.Tags.Keys -eq "ZABBIX.HOSTNAME"}

# Processando a lista de VMs
foreach ($VM in $VMs ) {

    # Selecionando os dados da listagem do Zabbix
    [Array]$ZBX_VM =  $ZBX_VMs | Where-Object {$PSItem.Name -eq $VM.Name}

    # Validando os status do AZURE com o Monitoramento VM
    if ($ZBX_VM.Length -gt 0) 
    {

        $VM_FULLSTATUS  =  Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Status
   


        if ($VM.PowerState -eq 'VM running' -and $ZBX_VM[0].Status -eq 1)
        {
            [String]::Format("Verificando de vai ser Ligado monitoramento do Host: {0}({1}) - {2}", $ZBX_VM[0].Name, $ZBX_VM[0].hostid, $VM.Name)

            # Validando o Delay para ligar 
            $VM_FULLSTATUS  =  Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Status   

            if ($VM_FULLSTATUS.Statuses[0].Time) {

                $RUNNING_TIME = (get-date) - $VM_FULLSTATUS.Statuses[0].Time
                $RUNNING_DIFFER = $RUNNING_TIME.TotalSeconds

                if ($RUNNING_DIFFER -gt $ZBX_DELAY) {
                    [String]::Format("Ligando monitoramento..!")
                    $retorno = StatusMonitoramento $ZBX_VM[0].hostid 0
                } else {
                    [String]::Format("Agurdando, ambiente ligou a menos de {0} segundos", $RUNNING_DIFFER)
                }
            }
        } 
        elseif ($VM.PowerState -ne 'VM running' -and $ZBX_VM[0].Status -eq 0)
        {
            [String]::Format("Desligando monitoramento do Host: {0}({1}) - {2}", $ZBX_VM[0].Name, $ZBX_VM[0].hostid, $VM.Name)
            $retorno = StatusMonitoramento $ZBX_VM[0].hostid 1
        }
        else
        {
             [String]::Format("Nada a fazer: {0}({1})", $ZBX_VM[0].Name, $ZBX_VM[0].hostid)
        }
    }
    else 
    {
         [String]::Format("VM nao monitorada: {0}", $VM.Name)
    }
}

