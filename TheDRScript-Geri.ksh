#!/bin/ksh
#
#
#
#This script is to generate the DR commands and place them on the filers
#You can run it against datacenters, it is going to recognize if the filer in the DC is snapmirroring
#   and if yes, then generates the commands, and uploads to the filer
#
#For example TheDRScript_2 -dr brn will generate the command on the Bern filers
#It will generate the following files in the directory /santeam/ConfigDB/DR_Scripts/
# - break_brn0sanfiler0x
# - map_brn0sanfiler0x_tierN
# - unmap_brn0sanfiler0x
# - resync_brn0sanfiler0x
#
# and to inform the vm team:
# - info_LOB_tierx
# 
#The input file is the "map file", in the fomrat of: DataCenter_map.txt in the folder /santeam/ConfigDB/DR_Scripts/
#For example /santeam/ConfigDB/DR_Scripts/brn_map.txt
#
#Once the files are generated, they will be uploaded to the filers into the folder
#"/etc/CITCO_DR"
#
#Author:   Geri
#Version:  0.1 Beta
#Date:     06/18/2013
#
#Version:  0.2 Still beta
#Date	   2014/02/10
#What is new in version 0.2
#	-added the upload switch (-u)
#	-added dc/vol switch (-dc/-v)
#	-fixed qtree snapmirror break issue
#
#Version:  0.21
#Date	   2014/04/09
#	-changed the command in the info_ files to use the lunSearch db directly
#	 if you change the path for the lunSearch db, you need to update MapInfoDir variable in the Main part
#	-added error checking for the map file
#
#Version:  0.22
#Date	   2014/04/15
#	-added igroup checking, the igroup db should be updated
#	-updated the map file format, now it handles multiple igroups, they should be devided by ","
#Version:  0.23
#Date	   2014/06/17
#	-bug fixed: there were " missing from a if statement
#	-bug fixed: ROLE was checked to decide if the DC is a dr dc. Introduced the var isDRDC
#Version:  0.30
#Date	   2014/06/19
#	-new switches: -b, -r, -i, -m, -um. sourceInScript and sendInfo routines were added to support those switches.
#Version:  0.31
#Date	   2014/06/21
#	-bug fixed: sourcing in map cmds, the filer names were incorrectly generated - fixed
# 	-bug fixed: qtree quiesce cmd were never to be called - fixed, if there is a qtree, then the generated cmd will be called.
#Verion:   0.5
#date	  2014/12/11
#	-separated the upload procedure, now it is an individual sub-command
#	-introduced the switches -sr, -sb

###################################
#           Procedures            #
###################################

Usage ()
{
	echo "${BOLD}Synopsis:$NORM"
	echo "   This script generates the DR scripts and place them on the filers in the given DataCenter"
	echo "   ${BOLD}Version: $VERSION"
	echo
	echo "${BOLD}Usage:$NORM"
	echo "   $MYNAME -dr|-s|-sb|-sr|-b|-r|-i|-um|-m DataCenterName [-u] [-v VolumeName|-dc SourceDCName]"
	echo "\nThe script has two main switches: -dr and -s." 
	echo "   $BOLD-s$NORM  When you use the \"-s\" switch it will check the Status of the given datacenter."
	echo "   $BOLD-sb$NORM Could be useful to check replication status during a DR event."
	echo "   $BOLD-sr$NORM Could be useful to check the restoration status of snapmirror replication after a DR event."
	echo "   $BOLD-dr$NORM When you use the \"-dr\" switch it will generate the DR scripts and places them in $BASEDIR/DataCenter folder"
	echo "   $BOLD-b$NORM  Breaks replication in the given datacenter"
	echo "   $BOLD-r$NORM  Resyncs mirrors in the given datacenter"
	echo "   $BOLD-i$NORM  Runs the generated \"info\" files and sends the to VmWare team"
	echo "   $BOLD-um$NORM Unmaps the previously mapped LUNs"
	echo "   $BOLD-m <tier>,<dc>$NORM  Maps the VmWare and Windows physical LUNs"
	echo "   $BOLD-u$NORM  Uploads the generated scripts to the filers in the DC."
	echo "   $BOLD-v$NORM  Selects only the volume names that specified. Useful when you working on a \"dryrun\" or on a partial DR."
	echo "   $BOLD-dc$NORM Selects only the volumes that are replicating from the specified datacenter. It is useful when you work on a"
	echo "       DR datacenter that contains snapmirrors from multiple location, but you want to have the DR script only for one DC."
	echo "       For example tor3 is a destination for ${BOLD}jrc, tor1, cur, sfo,$NORM but you need the sctipts only for ${BOLD}cur${NORM}."
	echo
	echo "   The script uses a \"mapfile\", named DataCenter_map.txt that should be in the \n   $BASEDIR folder. \n   The structure of the file should be like this:$BOLD"
	echo "      ###################### C&T/Group VMWare LUNs #########################################"
	echo "      /vol/gen0vmmsapp20/qt_gen0vmmsapp20/gen0vmmsapp20.lun   brn0sanfiler06  brn0ent04-fcp   CT      2"
	echo "      /vol/gen0vmmsapp25/qt_gen0vmmsapp25/gen0vmmsapp25.lun   brn0sanfiler02  brn0ent04-fcp   CT      2"
	echo "      ###################### Windows physical Machines #####################################"
	echo "      /vol/gen0mssql10ab/qt_gen0mssql10ab/gen0mssql10ab.lun   brn0sanfiler05  brn0mssql10a,brn0mssql10b,brn0mssql10c    SS      1$NORM"
	echo
	echo "   If the map file doesn't exist, then simply no LUN map/unmap commands will be generated."
	echo
	echo "${BOLD}Example:$NORM"
	echo "   ${BOLD}${BLUE_F}$MYNAME -dr brn -u $NORM"
	echo "          It will generate the DR scripts in the filers in Bern, and paces them in:"
	echo "             $BREAK_SM  - break snapmirror replications"
	echo "             $RESYNC_SM - resync snapmirror replications"
	echo "             $UNMAPLUN     - unmap command when we restore original state"
	echo "             ${TIER}x     - map command, devided by tiers"
	echo "   The generated files will be uploaded to $DR_Dir folder on all Bern filers"
	echo "   There will be \"info\" files devided by tiers and by BUs in the folder $BASEDIR/brn"
	echo
	echo "   ${BOLD}${BLUE_F}$MYNAME -dr tor3 -dc cur$NORM"
	echo "          It will generate the DR scripts in the filers in Toronto 3 only for the Curacao share. The result will$BOLD not$NORM be uploaded!"
	echo
	echo "   ${BOLD}${BLUE_F}$MYNAME -s brn$NORM"
	echo "          It will display the actual status of the snapmirrors in all the Bern filers."
	echo
	echo "   ${BOLD}${BLUE_F}$MYNAME -m 2,brn$NORM"
	echo "          It will map all the Windows physical and VM machines in Bern that belongs to tier 2."
	echo
	#exit 1
}

snapmirrorStatus ()
{
	for filer in $WorkOnFilers;do
		echo $BOLD$RED_F$filer$NORM
		if [ "$toGrepOff" == "" ];then
		   	ssh $filer snapmirror status 
		else
			ssh $filer snapmirror status | ggrep -v $toGrepOff
		fi
		echo
	done
}

sourceInScript ()
{
	cd $WORKDIR
	WorkOnFilers=`ls ${WhatToDo}_*$myTier 2>/dev/null | awk -F_ '{print $2}'`
	if [ "$WorkOnFilers" != "" ];then
		printf "You are about to $message in $DataCenter, do you want to continue? (y/any other key): "
		read userResponse
		if [ "$userResponse" == "y" ];then
			for filer in $WorkOnFilers; do
				echo "Connecting to $filer to $message..."
				if [ "$WhatToDo" == "break" ];then
					if [ -e qtreeBreak_$filer ];then
						ssh $filer source $BREAK_QT & 
					fi 
				fi
		   		ssh -n $filer $script &
			done
		else
			echo "OK, not touching anything..."
		fi
	else
		if [[ "$WhatToDo" == "map" || "$WhatToDo" == "info" ]];then
			insert=" for tier $myTier"
		fi
		echo "There is not a single $WhatToDo file$insert in $WORKDIR, nothing to do."
	fi
}

sendInfo ()
{
	SendFile="sendinfo_"
	cd $WORKDIR
	tierExist=`ls info*$myTier 2>/dev/null`
	if [ "$tierExist" == "" ] ;then
		echo "Tier $myTier does not exist in $DataCenter datacenter..."
	else
		echo "\nManually mapped LUN list for tier $myTier in $DataCenter datacenter\n" > $SendFile$myTier
		for bu in `ls info*$myTier`;do
			echo $bu | tee -a $SendFile$myTier
			./$bu | tee -a $SendFile$myTier
	 		echo | tee -a $SendFile$myTier
		done
		cat $SendFile$myTier | mailx -r $MAIL_SENDER -s "Manually mapped LUNS in $DataCenter for tier $myTier" $MAIL_REC
	fi
	rm sendinfo_$myTier	2>/dev/null
}

generateDRscripts ()
{
	cd $WORKDIR
	#first we do some error checking in the mapfile
	WrongInput="$WORKDIR/WrongEntries"
	if [ -e $MAPINPUT ];then
		echo "Checking the $MAPINPUT file..."
		awk '$1 !~ /^#/ {if (NF!=5) {print NR, $0}}' $MAPINPUT > $WrongInput
		awk -F/ '$1 !~ /^#/ {if ($2!="vol") {print NR, $0}}' $MAPINPUT >> $WrongInput
		awk -F/ '$1 !~ /^#/ {if (NF!=5) {print NR, $0}}' $MAPINPUT >> $WrongInput
		awk '$1 !~ /^#/ {print NR, $0}' $MAPINPUT | while myline=`line`;do
		echo $myline | read LineNumber LUN filer iGroups LOB Tier
			wrongiGroup=""
			for igroup in `echo $iGroups | sed 's/,/ /g'`;do
				goodiGroup=`egrep $igroup $IGroupDB_Dir/*`
				if [ "$goodiGroup" == "" ];then
					wrongiGroup="$wrongiGroup $igroup"
				fi
			done
			if [ "$wrongiGroup" != "" ];then
				echo "The igroup(s) $BOLD$MAGENTA_F$wrongiGroup$NORM are wrong in line $BOLD$MAGENTA_F$LineNumber$NORM in the map file!" | tee -a $WrongInput
			fi
		done
	fi

	
	#We need to check if there is any wrongly tiered entry in the map file
	testTiers=`seq $TierMIN $TierMAX`
	testTiers=`echo $testTiers | sed 's/ //g'`
	cat $MAPINPUT | egrep -v "^#|[$testTiers]$" >> $WrongInput # $WORKDIR/wrongmap_$filer 
	
	if [ -s $WrongInput ];then
		echo "${BOLD}\nThere are wrong entries in the mapinfo file, pls check $WrongInput!!!"
		cat $WrongInput
		echo "\nI cannot continue..."
		exit 6
	fi

	#Clear the working dir. In case of debug, disable the redirection
	rm -f $WORKDIR/* 2>/dev/null 

	#We check the role if the filers, if not snapmirroring, then it will be excluded
	printf "Rolecheck for: "
	for filer in $WorkOnFilers;do
		ROLE=`ssh $filer snapmirror status|awk '{print $3}'|grep Snapmirrored|sort|uniq`
		printf "$filer "
		if [ "$ROLE" == "Snapmirrored" ];then 
			SMfilers="$SMfilers $filer"
			isDRDC="yes"
		fi
	done
	echo
	WorkOnFilers=$SMfilers

	#We need to initialize the infoquerying files
	echo "Creating the header for the info files."
	for filer in $WorkOnFilers;do
		#ROLE=`ssh $filer snapmirror status|awk '{print $3}'|grep Snapmirrored|sort|uniq`
		if [ ! -z $isDRDC ]; then
			if [ -e $MAPINPUT ];then
				for i in `seq $TierMIN $TierMAX`;do
					for lob in `cat $MAPINPUT | egrep -v "^#" | grep -i $filer | egrep ${i}$ | awk '{print $4}' | sort -u`;do
						echo "cd $MapInfoDir" > info_${lob}_tier$i
					done
				done
			fi
		fi
	done
	
	for filer in $WorkOnFilers;do
		echo "Working on the filer $BOLD$filer${NORM}"
		#ROLE=`ssh $filer snapmirror status|awk '{print $3}'|grep Snapmirrored|sort|uniq`
		if [ ! -z $isDRDC ]; then
			#Generate the lun map commands, for this we use the mapinfo file
			#Also the lunSearch db must be up to date
			#For the selection we need to use -i, because we seen capital filer names
			#like Brn0sanfiler01
			#this "for" loop is for the tier-ing, it runs only if there is a loc_map.txt file in
			if [ -e $MAPINPUT ];then
				for i in `seq $TierMIN $TierMAX`;do
					echo "Working on tier $i..."
					#we need to ensure for the query we are in the correct folder
					cat $MAPINPUT | egrep -v "^#" | grep -i $filer | egrep ${i}$ | while myLine=`line`;do
						#place the content of a line into variables and create the commands
						echo $myLine | read LUN ActualFiler IGROUP LOB TIERNUM #initialize the variables for the actual line
						ActualFiler=`echo $ActualFiler | tr [:upper:] [:lower:]`
						echo "grep $LUN full_$DataCenter* | sed 's/full_//'" >> info_${LOB}_tier$i
						echo "lunSearch $LUN -f $filer" >> check_${LOB}_tier$i # | tee -a info_${LOB}_tier$i
						for igroup in `echo $IGROUP | sed 's/,/ /g'`;do
							echo "lun map $LUN $IGROUP" >> map_${filer}_tier$i # | tee -a map_${filer}_tier$i
							echo "lun unmap $LUN $IGROUP" >> unmap_${filer} # | tee -a unmap_${filer}
						done
						ALL_LOB="$ALL_LOB $LOB"
					done
					
					#make the script executable
					for LOB in $ALL_LOB;do 
						if [ -e info_${LOB}_tier$i ];then
							chmod 770 info_${LOB}_tier$i 2>/dev/null
							chmod 770 check_${LOB}_tier$i 2>/dev/null
						fi
					done
				done
			else
				echo "There is no $BOLD$MAPINPUT$NORM file, I am not generating map/unmap commands for $BOLD$DataCenter$NORM this time..."
			fi	
			
			#in the next line the -v will exclude the first and second line of the output
			#and also the snapmirrors that are sources
			#this way the script is useabe on the "source and destination" filers also like Cork and Dublin
			#depending on the command line swithches we select by volume or by source DC
			case $search in
				dc)
					ssh $filer snapmirror status | egrep -v "Snapmirror is on|Source" | egrep "^$SDCName" > tmp_$filer;;
				volume)
					ssh $filer snapmirror status | egrep -v "Snapmirror is on|Source" | awk -F: '$2 ~ /'$SVName'/ {print }'	 > tmp_$filer;;
				*)
					ssh $filer snapmirror status | egrep -v "Snapmirror is on|Source" > tmp_$filer;;
			esac
			vol=`cat tmp_$filer| awk '{print $2}' | awk -F: '{print $2}'`
			
			#Generate the commands and place in the ConfigDB
			echo "Generating break/resync/quiesce commands, and placing in $WORKDIR"
			for volume in $vol;do
				source=`cat tmp_$filer | egrep "$volume " | awk '{print $1}' | awk -F: '{print $1}'`
				if [[ `echo $volume | awk -F/ '{print $2}'` == "vol" ]];then
					echo snapmirror quiesce $volume >> qtreeBreak_$filer # | tee -a break_$filer
				fi
				echo snapmirror break $volume >> break_$filer # | tee -a break_$filer
				echo snapmirror resync -f -S ${source}:$volume $volume >> resync_$filer # | tee -a resync_$filer
			done

		else
			echo "The DC $RED_F$DataCenter$NORM is not a disaster recovery site..."
		fi	
		echo
		if [ -e tmp_$filer ];then
			rm tmp_$filer
		fi
	done

	
	#We do some error checking
	#Run the "check" scripts with a filter
	echo "Checking if the provided LUNs in the map file are exist on the given filer."
	echo "If you see a line starting with "No hit", then that entry is wrong in the map file."
	for i in `ls check*`;do
		echo $i
		./$i | grep "No hit" | tee -a NoHit_$DataCenter
	done
	
	echo "To upload the generated scripts, run $MYNAME -u <DataCenter>"

}
incrCounter ()
{
	errorMSG=`cat $tempErrorLog | ggrep -v "Connection to $filer closed by remote host"`
	if [ -z $errorMSG ];then
		fileCounter=$(($fileCounter+1))
	else
		echo "There was an issue with \"$ulCommand\" uploading to $filer" >> $ErrorLog
		echo $errorMSG >> $ErrorLog
		((errCounter=errCounter+1))
	fi
}

Upload ()
{
	sumCounter=0
	tempErrorLog="TempLog.txt"
	ErrorLog="UpldErr.log"
	errCounter=0
	> $ErrorLog
	if [[ -s $WrongInput || -s NoHit_$DataCenter ]];then
		echo "There were issues with the $MAPINPUT file, pls check, I cannot upload..."
	else
		#upload the generated files to the actual filer
		echo "\nUpload was requested, uploading..."
		for filer in $WorkOnFilers;do
			echo "Working on $filer"
			fileCounter=0
			for i in `seq $TierMIN $TierMAX`;do
				if [ -e map_${filer}_tier$i ];then
					ulCommand="map_${filer}_tier$i"
					echo "Uploading $ulCommand"
					ssh $filer wrfile $TIER$i < map_${filer}_tier$i 2>$tempErrorLog
					incrCounter
				fi
			done

 	 		# there is qtree/vol replication or resync/unmap
 			if [ -e qtreeBreak_$filer ];then
				ulCommand="qtreeBreak_$filer"
				echo "Uploading $ulCommand"
				ssh $filer wrfile $BREAK_QT < qtreeBreak_$filer 2>$tempErrorLog
				incrCounter
			fi
			if [ -e break_$filer ];then
				ulCommand="break_$filer"
				echo "Uploading $ulCommand"
				ssh $filer wrfile $BREAK_SM < break_$filer 2>$tempErrorLog
				incrCounter
			fi
			if [ -e resync_$filer ];then
				ulCommand="resync_$filer"
				echo "Uploading $ulCommand"
				ssh $filer wrfile $RESYNC_SM < resync_$filer 2>$tempErrorLog
				incrCounter
			fi
			if [ -e unmap_$filer ];then
				ulCommand="unmap_$filer"
				echo "Uploading $ulCommand"
				ssh $filer wrfile $UNMAPLUN < unmap_${filer} 2>$tempErrorLog
				incrCounter
			fi
			if [ $fileCounter -gt 0 ];then
				echo "I uploaded $fileCounter files to $filer"
			fi
			((sumCounter=sumCounter+fileCounter+errCounter))
		done
	fi
	if [ $sumCounter -gt 0 ];then
		echo "I have uploaded the scripts to the filers in $DataCenter"
		if [ -s $ErrorLog ];then
			echo "There were $errCounter issues out of $sumCounter tries uploading the files in $DataCenter:"
			cat $ErrorLog
		fi
	else
		echo "There were no files to upload for $YELLOW_F$BOLD$DataCenter$NORM datacenter!!"
	fi

	rm -f $tempErrorLog $ErrorLog 2>/dev/null
}

###########################
#       Main program      #
###########################


#Colors. The if is because linux handles colors differently
if [ -e /etc/release ];then
	BOLD="\033[1m"
	NORM="\033[0m"
	YELLOW_F="\033[33m"; YELLOW_B="\033[43m"
	RED_F="\033[31m"
	MAGENTA_F="\033[35m"
	CYAN_F="\033[36m"
	BLUE_F="\033[34m"
else
	BOLD=$'\e[1m'
	NORM=$'\e[0m'
	YELLOW_F=$'\e[33m'; YELLOW_B=$'\e[43m'
	RED_F=$'\e[31m'
	MAGENTA_F=$'\e[35m'
	CYAN_F=$'\e[36m'
	BLUE_F=$'\e[34m'
fi


DR_Dir="/etc/CITCO_DR"
BREAK_QT="$DR_Dir/qtree_break_mirrors"
BREAK_SM="$DR_Dir/break_mirrors"
RESYNC_SM="$DR_Dir/resync_mirrors"
LUNMAP="$DR_Dir/map_luns"
UNMAPLUN="$DR_Dir/unmap_luns"
TIER="$DR_Dir/map_tier_"
TierMIN=1
TierMAX=3

BASEDIR="/santeam/ConfigDB/DR_Scripts"
MYNAME=TheDRScript
VERSION=0.5

#Parameter handling
#At least 2 parameters must be passed, first we check this
if [ $# -lt 2 ]; then
	echo "Too few arguments!"
	Usage
	exit 11
fi

#The first switch is the "main command", it should be handled differently then the rest
case $1 in
	-s)  WhatToDo="smstatus";;
	-sb) WhatToDo="smbreak";;
	-sr) WhatToDo="smresync";;
	-dr) WhatToDo="generate";;
	-r)  WhatToDo="resync";;
	-b)	 WhatToDo="break";;
	-m)  WhatToDo="map"
		 UsedSwitch="-m";; #UsedSwitch is for an error message
	-u)  WhatToDo="upload";;	 
	-um) WhatToDo="unmap";;
	-i)  WhatToDo="info"
		 UsedSwitch="-i";;
	*)   echo "Wrong parameter!"
		Usage
		exit 21;;
esac

shift

#We need to check the second parameter that should be a dc
a=`echo $1|sed 's/^\(.\).*$/\1/'`
if [[ $a == "-" ]];then
	echo "\nWrong parameter $BOLD$1$NORM, it cannot be a switch...\n"
	Usage
	exit 27
else
	if [[ "$WhatToDo" == "map" || "$WhatToDo" == "info" ]];then
		echo $1 | grep "," > /dev/null
		if [ $? == 0 ]; then
			echo $1 | sed 's/,/ /' | read myTier DataCenter
			for tier in `seq $TierMIN $TierMAX`;do
				Tiers="$Tiers$tier"
			done
			echo $myTier | egrep [$Tiers] >/dev/null
			if [ $? != 0 ];then
				echo "Tier $BOLD$myTier$NORM is incorrect, it must be between $TierMIN and $TierMAX\nExiting..."
				exit 31
			fi
		else
			echo "You specified $BOLD$WhatToDo$NORM, the parameter for that should be: tier,datacenter; for example $UsedSwitch 1,mia\nExiting..."
			exit 30
		fi
	else
		DataCenter=$1
	fi
fi

shift

#if we still have parameters, that should be handled
while [ ! -z "$1" ]; do
	case "$1" in
		-v) 
			if [ "$search" == "dc" ]; then
				echo "You cannot specify source dc and vol in the same time..."
				exit 22
			else
				flag="volume"
			fi;;
		-dc) 
			if [ "$search" == "volume" ]; then
				echo "You cannot specify source dc and vol in the same time..."
				exit 23
			else
				flag="datacenter"
			fi
		;;
		*)	case $flag in
				volume)
					a=`echo $1|sed 's/^\(.\).*$/\1/'`
					if [ $a == "-" ];then
						echo "Wrong parameter $1\n"
						Usage	
						exit 24
					else
						search="volume"
						SVName="$1"
					fi
				;;
				datacenter)
					a=`echo $1|sed 's/^\(.\).*$/\1/'`
					if [ $a == "-" ];then
						echo "Wrong parameter $1\n"
						Usage
						exit 25
					else
						search="dc"
						SDCName="$1"
					fi
				;;
				*)
					echo "Wrong parameter $1\n"
					Usage
					exit 26
			esac
	esac
	shift
done

#Next line is to print out the parameters for troubleshooting
#echo What:$WhatToDo, DRDC:$DataCenter, Flag:$flag, Upload:$UpLoad, Search:$search, SeachDC:$SDCName, SearchVol:$SVName

if [ -z $FILERS ]; then
	echo "Initiating \$FILERS variable."
	. /opt/CITCOSan/Drivers/Driver_init
fi

#A few more variables
WORKDIR="$BASEDIR/$DataCenter"
WrongInput="$WORKDIR/WrongEntries"
NOTMIRRORING="is not a DR filer, nothing to do with it..."
MAPINPUT="$BASEDIR/${DataCenter}_map.txt"
WorkOnFilers=`for j in $FILERS; do echo $j; done | egrep "$DataCenter"`
MapInfoDir="/santeam/ConfigDB/OfflineLunDB"
IGroupDB_Dir="/santeam/ConfigDB/igroupDB"
MAIL_SENDER="CTM-OPS-IOS-SAN@citco.com"
MAIL_REC="CTM-OPS-IOS-Wintel@citco.com,CTM-OPS-IOS-SAN@citco.com"

if [ ! -e $WORKDIR ];then
	mkdir $WORKDIR
fi

cd $WORKDIR


#According to the request we set what script should be run, set the message and tier
case $WhatToDo in
        smstatus)	
			snapmirrorStatus;;
		smbreak)
			toGrepOff="Broken"
			snapmirrorStatus;;
		smresync)
			toGrepOff="Snapmirrored"	
			snapmirrorStatus;;
        generate)	
			generateDRscripts;;
		resync)	
			script="source /etc/CITCO_DR/resync_mirrors"
			message="resync replication"
			myTier=""
			sourceInScript;;
		break)		
			script="source /etc/CITCO_DR/break_mirrors"
			message="break replication"
			myTier=""
			sourceInScript;;
		map)		
			script="source /etc/CITCO_DR/map_tier_$myTier"
			message="map tier $myTier"
			#myTier is already set at the parameter handling part
			sourceInScript;;
		unmap)
			script="source /etc/CITCO_DR/unmap_luns"
			message="unmap luns"
			myTier=""
			sourceInScript;;			
		info)		
			sendInfo;;
		upload)
			Upload;;	
        *) 
			Usage;;
esac

