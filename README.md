# Amazon RDS Replication
This is a shell script that can be run as a scheduled job to regularly replication a production RDS (Relational database service) on AWS to another RDS instance (i.e. staging).

You simply need to fill in the AWS key + secret, as well as the RDS instance ID and the replciated instance ID (the id of the instance you want to replicate to). This script is great for maintaining an up-to-date copy of a site's database on a staging server, for example. 
