
# User definion
$CUSTOMER_FULL = "SKA"

##### Preparing variables ##########################################
$LOCATION = "East US 2"
$RSV_NAME = "RSV-" + $CUSTOMER_FULL
$RSG_BACKUP = "GRPRD-" + $CUSTOMER_FULL + "-BACKUP"
$PLAN_NAME = "PLAN-BKP-" + $CUSTOMER_FULL +"-Default"
####################################################################

#### Validating Resource Group ####
$RSG = Get-AzureRmResourceGroup -Name $$RSG_BACKUP -Location $LOCATION

if (!$?) {
    $RSG = New-AzureRmResourceGroup -Name $$RSG_BACKUP -Location $LOCATION
}

#### Creating Recovery Services Vault 
$RSV =  New-AzureRmRecoveryServicesVault -Name $RSV_NAME  -ResourceGroupName $RSG.ResourceGroupName  -Location $LOCATION
Set-AzureRmRecoveryServicesBackupProperties -Vault $RSV -BackupStorageRedundancy LocallyRedundant

#### Preparing next backup time
$TODAY = Get-Date
$KIND = new-object System.DateTimeKind
$KIND.value__ = 1 # UTC
$DATE = New-Object system.datetime($TODAY.Year,$TODAY.Month,$TODAY.Day,18,00,00,$KIND)

$SCHED 		= Get-AzureRmRecoveryServicesBackupSchedulePolicyObject -WorkloadType AzureVM -BackupManagementType AzureVM
$SCHED.ScheduleRunTimes[0] = $DATE

#### Setting retentions
$RETENTION 	= Get-AzureRmRecoveryServicesBackupRetentionPolicyObject -WorkloadType AzureVM -BackupManagementType AzureVM
$RETENTION.IsYearlyScheduleEnabled = $false
$RETENTION.DailySchedule.DurationCountInDays = 15
$RETENTION.WeeklySchedule.DurationCountInWeeks = 5
$RETENTION.MonthlySchedule.DurationCountInMonths = 6
$RETENTION.MonthlySchedule.RetentionScheduleFormatType = 'Daily'
$RETENTION.MonthlySchedule.RetentionScheduleDaily[0].DaysOfTheMonth[0].Date = 0
$RETENTION.MonthlySchedule.RetentionScheduleDaily[0].DaysOfTheMonth[0].isLast = $true

#### Creating default backup policy
New-AzureRmRecoveryServicesBackupProtectionPolicy -Name $PLAN_NAME -WorkloadType AzureVM -BackupManagementType AzureVM -RetentionPolicy $RETENTION -SchedulePolicy $SCHED -VaultId $RSV.ID
