# WSFC Auto-Creation
Creates a WSFC on AWS. Gathers IPs automatically using EC2 metadata. Needs to be run as a user with admin privileges on all nodes.
* Update $WSFCClusterName and $ClusterNodes in the script to match your desired cluster name and existing instance names.
* Expects each instance to have 3 IPs - 1 x primary (default) and 2 x secondary (1 for WSFC, 1 for whatever clustered role is to be added later).
* Expects shared storage to exist (e.g. iSCSI LUNs from FSx for NetApp ONTAP).
* Optionally run the SOFS script afterwards to enable the SOFS role.
