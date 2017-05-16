#!/bin/bash
# RDS Replication snapshot and restore script
# Written by Shift8 Web www.shift8web.ca

snapid="snap-`date "+%Y%m%d-%H%M%S"`"
datetime=`date "+%Y-%m-%d %H:%M:%S"`
backupdbid="backup-id"
logfile="/var/log/rds-reporting.log"

# set env variables
export JAVA_HOME=/usr/lib/jvm/java-7-oracle
export AWS_RDS_HOME=/opt/aws
export PATH=$PATH:$AWS_RDS_HOME/bin
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=
export AWS_DEFAULT_OUTPUT=text

#config options
securitygroup="securitygroup"
paramsgroup="default.mysql5.5"
avail_zone="us-east-1d"
cred_file="/opt/aws/credential-file-path"
aws_path="/usr/local/bin"
emails="your@email.com,second@email.com"

#rds verifying commands
snapshot_availability="$aws_path/aws rds describe-db-snapshots | grep -i -w $snapid | grep available | wc -l"
instance_deleting="$aws_path/aws rds describe-db-instances | grep -i -w $backupdbid | grep deleting | wc -l"
sec_changes="$aws_path/aws rds describe-db-instances --db-instance-identifier $backupdbid | grep SECURITYGROUP | grep -i -w $securitygroup | grep active |wc -l"
param_changes="$aws_path/aws rds describe-db-instances --db-instance-identifier $backupdbid | grep PARAMETERGROUP | grep -i -w $paramsgroup | grep in-sync |wc -l"
instance_availability="$aws_path/aws rds describe-db-instances | grep -i -w $backupdbid | grep available | wc -l"


wait_until()
{
        result=`eval $* | sed 's/ //g'`
        if [ $result -eq 0 ]
        then
                sleep 20
                wait_until $*
        fi
}


wait_until_delete()
{
        result=`eval $* | sed 's/ //g'`
        if [ $result -ge 1 ]
        then
                sleep 20
                wait_until_delete $*
        fi
}

# prep log file
echo "RDS $backupdbid Replication Log: " $datetime > $logfile 2>&1
echo -e "-----------------------------------------------" >> $logfile 2>&1
echo -e "" >> $logfile 2>&1

# check if the rds instance exists already and delete if it does
echo -e "Checking if RDS $backupdbid instance already exists .. " >> $logfile 2>&1
exists=`$aws_path/aws rds describe-db-instances | grep -i $backupdbid  | wc -l`
if [ $exists = '0' ]
then
        echo "RDS Instance $backupdbid does not exist .." >> $logfile 2>&1
else
        echo "Deleting RDS instance $backupdbid ..  may take a few minutes to complete" >> $logfile 2>&1
        $aws_path/aws rds delete-db-instance --db-instance-identifier $backupdbid --skip-final-snapshot >> $logfile 2>&1
        if [ "$?" -ge 1 ]
        then
                echo -e "***RDS $backupdbid JOB, THERE WERE ERRORS***" >> $logfile 2>&1
                cat $logfile | mail -s "RDS $backupdbid REPLICATION Job failed" -r "RDS Replication Script <noreply@yourdomain.com>" $emails
                exit 1
        fi
        echo "Waiting until instance is fully deleted .. " >> $logfile 2>&1
        sleep 30
        wait_until_delete $instance_deleting
fi

# create snapshot from main DB
echo -e "Creating snapshot based on main RDS .." >> $logfile 2>&1
$aws_path/aws rds create-db-snapshot --db-instance-identifier wdwdtdatabase --db-snapshot-identifier $snapid >> $logfile 2>&1
if [ "$?" -ge 1 ]
then
        echo -e "***RDS $backupdbid REPLICATION JOB, THERE WERE ERRORS***" >> $logfile 2>&1
        cat $logfile | mail -s "RDS $backupdbid REPLICATION Job failed" -r "RDS Replication Script <noreply@yourdomain.com>" $emails
        exit 1
fi
wait_until $snapshot_availability

# restore from snapshot to new RDS (which should have been deleted already)
echo -e "Creating new RDS from snapshot .." >> $logfile 2>&1
$aws_path/aws rds restore-db-instance-from-db-snapshot --db-instance-identifier $backupdbid --db-snapshot-identifier $snapid --db-instance-class db.m1.small >> $logfile 2>&1
if [ "$?" -ge 1 ]
then
        echo -e "***RDS $backupdbid REPLICATION JOB, THERE WERE ERRORS***" >> $logfile 2>&1
        cat $logfile | mail -s "RDS $backupdbid REPLICATION Job failed" -r "RDS Replication Script <noreply@yourdomain.com>" $emails
        exit 1
fi
wait_until $instance_availability
# set the security and parameter groups
echo -e "Changing security and parameter groups .." >> $logfile 2>&1
$aws_path/aws rds modify-db-instance --db-instance-identifier $backupdbid --db-parameter-group-name $paramsgroup --db-security-groups $securitygroup >> $logfile 2>&1
if [ "$?" -ge 1 ]
then
        echo -e "***RDS $backupdbid REPLICATION JOB, THERE WERE ERRORS***" >> $logfile 2>&1
        cat $logfile | mail -s "RDS $backupdbid REPLICATION Job failed" -r "RDS Replication Script <noreply@yourdomain.com>" $emails
        exit 1
fi
wait_until $sec_changes
wait_until $param_changes

# reboot the new instance to apply security groups
echo -e "Rebooting server to apply security groups" >> $logfile 2>&1
$aws_path/aws rds reboot-db-instance --db-instance-identifier $backupdbid
wait_until $instance_availability

# Wait to give the server time to accept connections
sleep 120

# Run Lucian's PHP script that runs all these mysql queries on the new instance
echo -e "Running PHP MySQL query script .." >> $logfile 2>&1
/usr/bin/php /usr/local/bin/rds-reporting-queries.php >> $logfile 2>&1
if [ "$?" -ge 1 ]
then
        echo -e "***RDS $backupdbid REPLICATION JOB, THERE WERE ERRORS***" >> $logfile 2>&1
        cat $logfile | mail -s "RDS $backupdbid REPLICATION Job failed" -r "RDS Replication Script <noreply@yourdomain.com>" $emails
        exit 1
fi

# delete the created snapshot
echo -e "Deleting snapshot $snapid .." >> $logfile 2>&1
$aws_path/aws rds delete-db-snapshot --db-snapshot-identifier $snapid >> $logfile 2>&1
if [ "$?" -ge 1 ]
then
        echo -e "***RDS $backupdbid REPLICATION JOB, THERE WERE ERRORS***" >> $logfile 2>&1
        cat $logfile | mail -s "RDS $backupdbid REPLICATION Job failed" -r "RDS Replication Script <noreply@yourdomain.com>" $emails
        exit 1
fi

echo -e "RDS $backupdbid instance snapshot script completed successfully!" >> $logfile 2>&1

#cat $logfile | mail -s "RDS $backupdbid Snapshot : Complete with no Errors" -r "RDS Replication Script <noreply@yourdomain.com>" $emails

exit 0
