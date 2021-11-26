# Create SOFS
$SOFSClusterName = "SOFS11"
Add-ClusterScaleOutFileServerRole -Name $SOFSClusterName -Cluster $WSFCClusterName

# Check for available storage
$AvailableClusterDisks = @( Get-ClusterResource | Where-Object {$_.ResourceType -eq "Physical Disk" -And $_.OwnerGroup -eq "Available Storage"} | Select-Object -ExpandProperty Name )
# If there are multiple available disks, just add one - this is just a test after all
Add-ClusterSharedVolume -Name ([String]$AvailableClusterDisks[0])