## 
#
# Criando VM Linux 
#
##

# Local
$LOCATION = "Brazil South"

# Grupo de Recurso
$RSG_NAME = "GRPRD-FRUKI-BI-01"

# VM Name
$VMNAME = "VML-PRD-VER-03"

# VM Size
$VMSIZE = "Standard_B2S"

# Disk kind
$STG_KING = "Standard_LRS" 


# Configuração da VNEt 
$VNET =  "VNET-GRPRD-FRUKI"
$SUBNET = "Subnet-Producao"

$IP = "10.80.0.33"

##### 
#  Preparing variables .. 
#####

# Storage Account_Name 
$STGNAME = "stg" + ($VMNAME.Replace("-", "")).ToLower()


# Linux Version
$PUBLISHER= "OpenLogic"
$OFFER = "CentOS"
$SKU = "7.5"
$VERSION = "latest"

#####



function Get-Subnet () {
    $RETURN_SUBNET = ""    
    $VNETs = Get-AzureRmVirtualNetwork
    foreach ($VN in $VNETs) { 
        if ($VN.Name -eq $VNET) {
            $SUBNETs = $VN | Get-AzureRmVirtualNetworkSubnetConfig
            foreach ($SUB in $SUBNETs) {
                if ($SUB.Name -eq $SUBNET) {
                    $RETURN_SUBNET = $SUB                    
                }                 
            }
        }
    }
    $RETURN_SUBNET
}




#### Validating Resource Group ####
$RSG = Get-AzureRmResourceGroup -Name $RSG_NAME -Location $LOCATION

if (!$?) {
    $RSG = New-AzureRmResourceGroup -Name $RSG_NAME -Location $LOCATION
}


#### Validating Storage Account ####
$STG = Get-AzureRmStorageAccount -ResourceGroupName $RSG.ResourceGroupName -Name $STGNAME
if (!$?) {
    $STG = New-AzureRmStorageAccount -ResourceGroupName $RSG.ResourceGroupName -Name $STGNAME -SkuName $STG_KING -Location $LOCATION -Kind StorageV2 -AccessTier Hot
}


# Criando container
$STG_CONTAINER = Get-AzureRmStorageContainer -StorageAccount $STG -Name "vhds"
if (!$?) {
    $STG_CONTAINER = New-AzureRmStorageContainer -StorageAccount $STG -PublicAccess Blob -Name "vhds"
}

# Configurando a NIC # 
$SUB = Get-Subnet
$IPconfig = New-AzureRmNetworkInterfaceIpConfig  -Name ("IPconfig-"+$VMNAME) -PrivateIpAddressVersion IPv4 -PrivateIpAddress $IP -Subnet $SUB
$NIC = New-AzureRmNetworkInterface -Name ($VMNAME + "-NIC") -ResourceGroupName $RSG.ResourceGroupName -Location $LOCATION -IpConfiguration $IPconfig


$CRED = Get-Credential



# Criando o disco
$OSDisk = $STG.PrimaryEndpoints.Blob.ToString() + "vhds/" + $VMNAME + "-OSDISK.vhd"



# Criando VM
$VM = New-AzureRmVMConfig -VMName $VMNAME -VMSize $VMSIZE
$VM = Set-AzureRmVMOperatingSystem -VM $VM -Linux -ComputerName $VMNAME -Credential $CRED
$VM = Set-AzureRmVMSourceImage -VM $VM -PublisherName $PUBLISHER -Offer $OFFER -Skus $SKU -Version $VERSION
$VM = Set-AzureRmVMOSDisk -VM $VM -Name ($VMNAME + "-OSDISK") -VhdUri $OSDisk -Caching ReadOnly -CreateOption fromImage
$vm = Add-AzureRmVMNetworkInterface -VM $VM -Id $NIC.Id

New-AzureRmVM -VM $VM -ResourceGroupName $RSG.ResourceGroupName -Location $LOCATION -Verbose