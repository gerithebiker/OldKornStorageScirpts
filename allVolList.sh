#!/bin/ksh
#
#
#This script scans filers for all the volume sizes on all filers
#If one parameter is passed, it scans only the given filer
#
#The purpose is to keep track of the number of volumes
#Written by Geri, 04/10/2012
#Version 1.0
#Runs every Saturday night as a cron job

Usage ()
{
 echo "\nBad parameters!"
 echo "   It handles one or no parameter"
 echo "   If one parameter was given, then only that one filer is going to be scanned"
 echo "   The output is placed in a file called FullVolList_FILERNAME in the working directory"
 echo "   If no parameter passed, then all the filers going to be scanned"
 echo "   and the output placed in gen0vmsucon01:/santeam/NumberOfVolumes"
}

#
if [ $# -gt 1 ]
then
        Usage
        exit 1
fi


#check the version (not necessary in this script)
#if [ `ssh $1 version|awk '{print $3}'|awk '{ FS = "." };{print $1}` -lt 8 ]
#        then
#                echo "Not supported OS verson on filer $1"
#                exit 2
#fi

#check if a filer name is passed
if [ $1 <> "" ]
	then
		FILERS=$1
		FileName="ActualVolList_$1"
	else
		. /opt/CITCOSan/Drivers/Driver_init
		name=`date +%y-%m-%d`
		FileName="/santeam/ConfigDB/NumberOfVolumes/FullVolList_$name"
fi

#remove the output, just in case there was an unsuccessful run of the script previously
rm $FileName

#read all the volumes and select the containing aggregate line and the vol name line
#and place it in a temp file for later usage
for FILER in $FILERS 
do
	echo "Working on $FILER"
	#the vol could be offline...
	ssh $FILER vol status -v|egrep "online|offline|Containing"|grep -v Plex > tmp
	cat tmp | while myLine=`line`

	do
		#test if the line contains the vol name
		tst=`echo $myLine|awk '{print $2}'`

		if [ "$tst" = "aggregate:" ]
			then
				aggr=`echo $myLine|awk '{print $3}'|sed "s/\'//g"`
			else
				vol=`echo $myLine|awk '{print $1}'`
				state=`echo $myLine|awk '{print $2}'`
				#volsize=`ssh $FILER vol size $vol|grep "vol size: Flexible"|awk '{print $8}'`
			fi
			if [ $tst == "aggregate:" ]
				then
					volsize=`ssh -n $FILER vol size $vol|grep "vol size: Flexible"|awk '{print $8}'`
					unit=`echo $volsize | sed "s/.$//" | sed -e "s/^.*\(.\)$/\1/"`
					volsize=`echo $volsize| sed "s/..$//"`
					#if the unit is not g (gigabytes), then convert it to gigs
					case "$unit" in
						'k')
						#the next expression is the floor function for volsize
						volsize=`expr $((($volsize - $volsize % 1048576) / 1048576))`
						;;
						'm')
						Size=`expr $((($volsize - $volsize % 1024) / 1024))`
						;;
					esac
					echo "$FILER;$aggr;$vol;$state;$volsize"
					echo "$FILER $aggr $vol $state $volsize" >> $FileName
			
			fi
	done
	rm tmp
done 

#remove all vol0 from the result
cat $FileName | grep -v vol0 > tmp
rm $FileName
mv tmp $FileName
