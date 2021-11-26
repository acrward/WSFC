<#
This script gathers all the EC2 IP and secondary IPs associated with all of the nodes specified, creates a cluster using the first
of the secondary IPs associated with the EC2 NIC, renames the cluster network resources, sets the IP owners, and sets the cluster name dependency
to either/or for all of the nodes in the cluster. It also adds all available storage to the cluster.
#>

## Populate the cluster node names and set the clustername for the WSFC
$WSFCClusterName = "WSFC11"
$ClusterNodes = ("SQLDev1", "SQLDev2")

Write-Output "Node Names: " $ClusterNodes
Write-Output "WSFC Name: " $WSFCClusterName

# Create and populate a hashtable for IPs assigned to cluster node ENIs
$ClusterNodesEC2IPsHashTable = @{}
Foreach ($ClusterNode in $ClusterNodes) {
    $value = Invoke-Command -Computername $ClusterNode -Scriptblock {
        [string]$token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT –Uri http://169.254.169.254/latest/api/token    # Get the token for use in metadata retrieval
        $nodeEC2MAC = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/network/interfaces/macs/   # Get the MAC address of the ENI
        $nodeEC2IPsArray = (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/network/interfaces/macs/$nodeEC2MAC/local-ipv4s).Split("`n") # Store the ENI IPs in an array
        $nodeEC2IPsArray    # Return to $value
    }
    $ClusterNodesEC2IPsHashTable.add( $ClusterNode, $value )     # Add the IPs of the current node in the loop to my hashtable
}

# Create a Cluster using the IPs from above
New-Cluster -Name $WSFCClusterName -Node $ClusterNodes -AdministrativeAccessPoint ActiveDirectoryAndDNS -StaticAddress $ClusterNodes.ForEach( { $ClusterNodesEC2IPsHashTable[$_][1] } ) 

# Rename Cluster IP and Disk Resources
Write-Output "Renaming Cluster IP Resources"
$ClusterIPResources = Get-ClusterResource | Where-Object {$_.ResourceType -eq "IP Address"} | Select-Object -ExpandProperty Name
$ClusterIPResources.ForEach( { (Get-ClusterResource -Name "$_").Name = Get-ClusterResource -Name "$_" | Get-ClusterParameter -Name Address | Select-Object -ExpandProperty Value } )
(Get-ClusterResource | Where-Object {$_.ResourceType -eq "Physical Disk" -and $_.OwnerGroup -eq "Cluster Group"}).Name = "Quorum Disk"
(Get-ClusterGroup "Cluster Group").Name = $WSFCClusterName
(Get-ClusterResource | Where-Object {$_.ResourceType -eq "Network Name" -and $_.OwnerGroup -eq $WSFCClusterName}).Name = $WSFCClusterName

# Set possible owners for IP addresses - each node should only own its own IP
$ClusterNodes.ForEach( { Get-Cluster -Name $WSFCClusterName | Get-ClusterResource -Name ([String]$ClusterNodesEC2IPsHashTable.$_[1]) | Set-ClusterOwnerNode -Owners ([String]$_) })

# Set dependencies for the cluster name object to be either/or for the node IP addresses
Set-ClusterResourceDependency -Resource "Cluster Name" -Dependency ("[" + ($ClusterNodes.ForEach( { $ClusterNodesEC2IPsHashTable[$_][1] } ) -join '] or [') + "]")

# Set Cluster Name Object Permissions on Default AD Computers Container

function Get-ADClusterComputerAccessRules {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Security.Principal.NTAccount] $IdentityReference
    )

    New-ADAccessRule -IdentityReference $IdentityReference -Rights 'ReadProperty, GenericExecute'
    New-ADAccessRule -IdentityReference $IdentityReference -Rights 'ReadProperty, CreateChild' -ObjectType 'bf967a86-0de6-11d0-a285-00aa003049e2'   # Description
}

function New-ADAccessRule {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Security.Principal.NTAccount] $IdentityReference,
        [Parameter(Mandatory)]
        [System.DirectoryServices.ActiveDirectoryRights] $Rights,
        [System.Security.AccessControl.AccessControlType] $Type = $([System.Security.AccessControl.AccessControlType]::Allow),
        [Guid] $ObjectType = $([Guid]::Empty),
        [System.DirectoryServices.ActiveDirectorySecurityInheritance] $Inheritance ="All",
        [Guid] $InheritedObjectType = $([Guid]::Empty)
    )

    New-Object System.DirectoryServices.ActiveDirectoryAccessRule ($IdentityReference,$Rights,$Type,$ObjectType,$Inheritance,$InheritedObjectType)
}

$specificADComputersContainer = Get-ADDomain | Select-Object -ExpandProperty ComputersContainer
$Cluster             = Get-ADComputer -Identity $WSFCClusterName
$acl                 = get-acl "ad:$specificADComputersContainer"
$IdentityReference   = New-Object System.Security.Principal.NTAccount (Get-ADDomain).NetBIOSName,$Cluster.SamAccountName
$ExpectedAccessRules = @(Get-ADClusterComputerAccessRules -IdentityReference $IdentityReference)
$CurrentAccessRules  = @($Acl.Access | Where-Object IdentityReference -eq $IdentityReference)
$MissingAccessRules  = @(Compare-Object -ReferenceObject $CurrentAccessRules -DifferenceObject $ExpectedAccessRules | Where-Object SideIndicator -eq '=>')

$MissingAccessRules.ForEach{$Acl.AddAccessRule($_.InputObject)}

Set-acl -aclobject $acl "ad:$specificADComputersContainer"

# Run some tests
Move-ClusterGroup -Name "Cluster Group" | Format-Table
Move-ClusterGroup -Name "Available Storage" | Format-Table
Move-ClusterGroup -Name "Cluster Group" | Format-Table
Move-ClusterGroup -Name "Available Storage" | Format-Table