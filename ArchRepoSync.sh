#!/bin/bash

#
# ArchRepoSync - (c) 2009 by Andre Herbst, Greifswald
#
# Changelog:
# 	2009 11 08
#		- initial release
#	2009 11 10
#		- small fix: wrong existence check befor moving .consistent db files
#	2009 12 01
#		- also restore packages from 'any' architecture when reverting to an old state
#	2010 01 28
#		- display iso image sync status ... and also clean up iso backups
#
#	2010 02 05
#		- added parameters to control arch and repo download
#
#	2010 02 24
#		- read package filenames from the desc files to check consistency
#
#	2010 02 28
#		- removed consistencycheck of .old databases
#
#	2010 03 16
#		- added md5 integrity check switch
#		- added check for missing any arch packages
#
#	2010 04 08
#		- consistency_check_only does not remove backups anymore
#
#	2010 08 22
#		- added copy-unsafe-links switch to rsync since some mirrors
#		are storing files outside the archlinux trees and point links
#		to them
#
#	2010 08 29
#		- added multilib repo
#
#	2010 10 06
#		- added gnome-unstable, kde-unstable, multilib-testing repos
#
#	2010 10 14
#		- excluded !x86_64 archs from multilib-testing
#
#	2010 10 24
#		- fixed include exclude rules to accept downloading a single arch
#
#	2011 05 28
#		- removed extra exclude rule for backup dir
#
#	2011 05 31
#		- added ignore-errors param to rsync
#
#	2013 11 18
#		- added 'none' arch and 'none' repo to skip package sync
#		- fixed iso sync
#
#	2013 11 23
#		- removed debug output of NOARCHS and NOREPOS
#


#
# CONFIGURATION
#


#mirror=rsync://distro.ibiblio.org/distros/archlinux
#mirror=rsync://ftp-stud.hs-esslingen.de/archlinux
mirror=rsync://mirrors.kernel.org/archlinux

# repos="core extra community community-testing multilib testing"
# archs="i686 x86_64"

repos="core extra community multilib community-testing gnome-unstable kde-unstable multilib-testing testing"
archs="i686 x86_64"
paralleldownloads=4

#
# END OF CONFIGURATION
#

ONLY_CHECK_CONSISTENCY=0
INTEGRITY_CHECK=0
VERBOSITY=0
PRINT_USAGE=0
ARG_ARCHS=""
ARG_NOARCHS=0
ARG_REPOS=""
ARG_NOREPOS=0

opt=!

while ! [ "$opt" = "?" ]
do
	getopts a:cfhim:p:r:v opt $*

	case $opt in
		a)
			ARG_ARCHS="$ARG_ARCHS $OPTARG"

			if [ "$OPTARG" = "none" ]
			then
				ARG_NOARCHS=1
				ARG_ARCHS=""
			else
				ARG_NOARCHS=0
			fi;;
		c)
			ONLY_CHECK_CONSISTENCY=1;;
		h)
			PRINT_USAGE=1;;
		i)
			INTEGRITY_CHECK=1;;
		m)
			mirror=$OPTARG;;
		p)
			paralleldownloads=$OPTARG;;
		r)
			ARG_REPOS="$ARG_REPOS $OPTARG"

			if [ "$OPTARG" = "none" ]
			then
				ARG_NOREPOS=1
				ARG_REPOS=""
			else
				ARG_NOREPOS=0
			fi;;
		v)
			VERBOSITY=$(( $VERBOSITY + 1));;
	esac
done

if [ $PRINT_USAGE -eq 1 ]
then
	echo "usage: [-chiv] [-a <arch>] [-r <repo>] [-m <mirror>] [-p <num parallel processes>]"
	echo "options:"
	echo " -a <arch>	select arch; one of {i686, x86_64}"
	echo " -r <repo>	select repo; one of	{core, extra, community,"
	echo "						community-testing, testing}"
	echo "		to specify multiple archs/repos you need to add the"
	echo "		-a/-r parameter multiple times"
	echo " -c		only check consistency"
	echo " -h		show help"
	echo " -i		do md5 integrity check"
	echo " -m <mirror>	use specified mirror"
	echo " -p <num>		use num parallel rsync instances"
	echo " -v		verbose"
	echo
	echo "example:	./sync.sh -v -a i686 -r core -r extra -r community"
	echo "		download core,extra,community repos for i686 architecture"
	echo

	exit 0
fi

if ! [ "$ARG_ARCHS" = "" ] || [ $ARG_NOARCHS -eq 1 ]
then
	archs="$ARG_ARCHS"
fi

if ! echo $archs | grep any && ! [ $ARG_NOARCHS -eq 1 ]
then
	archs="any $archs"
fi

if ! [ "$ARG_REPOS" = "" ] || [ $ARG_NOREPOS -eq 1 ]
then
	repos="$ARG_REPOS"
fi

log()
{
	verbositylvl=$1
	shift 1

	if [ $VERBOSITY -ge $verbositylvl ]
	then
		echo "$*" | tee -a sync.log
	else
		echo "$*" >> sync.log
	fi
}

errlog()
{
	echo "$*" >> sync.log
	echo "$*" 1>&2
}



consistencycheck()
{
	local repo=$1
	local arch=$2

	if ! [ "$arch" = "any" ]
	then
		DBFILE=$repo/os/$arch/$repo.db.tar.gz

		if ! [ -e $DBFILE ]
		then
			errlog \(EE\) $DBFILE not found
			return 1
		fi

		tar -xzOf $DBFILE --wildcards */desc | 
		(
			error=0
			lastline=""

			filename=""
			md5sum=""

			while read line
			do
				if [ "$lastline" == "%FILENAME%" ]
				then
					filename="$line"

					if [ -L "$repo/os/$arch/$filename" ] && ! [ -e "$repo/os/any/$filename" ]
					then
						errlog \(EE\) missing package: $repo/os/any/$filename
						error=1
					fi

					if ! [ -e "$repo/os/$arch/$filename" ]
					then
						errlog \(EE\) missing package: $repo/os/$arch/$filename
						error=1
					fi
				elif [ "$lastline" == "%MD5SUM%" ]
				then
					md5sum=$line

					if [ $INTEGRITY_CHECK -eq 1 ] && ( echo "$md5sum  $repo/os/$arch/$filename" | md5sum -c --quiet; [ $? -eq 1 ] )
					then
						errlog \(EE\) md5sum corruption of package: $repo/os/$arch/$filename ... deleting file

						if ! [ -e "$repo/os/$arch/$filename" ] || [ -L "$repo/os/$arch/$filename" ]
						then
							rm "$repo/os/any/$filename"
						else
							rm "$repo/os/$arch/$filename"
						fi
						error=1
					fi
				fi

				lastline="$line"
			done

			return $error
		)
	fi

	return $?
}



if ! [ $ONLY_CHECK_CONSISTENCY -eq 0 ]
then
	log 1 "*** only checking consistency: $(date)"
else
	log 1 "*** synchronization started: $(date)"
	log 1 \(II\) using mirror $mirror
	log 1 \(II\) using $paralleldownloads parallel rsync instances
	log 1 \(II\) repos: $repos
	log 1 \(II\) archs: $archs
fi

rsyncopts="-abv --copy-unsafe-links --no-motd --delete --ignore-errors --backup-dir=backup"

dcount=0
for repo in $repos
do
	ierules=""

	for arch in $archs
	do
		if ( [ "$repo" = "multilib" ] || [ "$repo" = "multilib-testing" ] ) && [ "$arch" != "x86_64" ]
		then
			continue
		fi

		mkdir -p $repo/os/$arch
		ierules="$ierules --include="$arch" --include="$arch/**""
	done
	ierules="$ierules --exclude="*""

	(
		if [ $ONLY_CHECK_CONSISTENCY -eq 0 ]
		then
			log 1 \(II\) syncing $repo/os ...

			rsync $rsyncopts $ierules $mirror/$repo/os/ $repo/os/ 2>> sync.log 1> /dev/null

			for arch in $archs
			do
				if ! [ "$arch" = "any" ]
				then
					for db in abs db files
					do
						if [ -e $repo/os/backup/$arch/$repo.$db.tar.gz.consistent ]
						then
							mv $repo/os/backup/$arch/$repo.$db.tar.gz.consistent $repo/os/$arch/
						fi
					done
				fi
			done

			log 1 \(II\) done syncing $repo/os.
		fi
	) &
	dcount=$(( $dcount + 1))

	if [ $dcount -ge $paralleldownloads ]
	then
		wait
		dcount=0
	fi
done

if [ $ONLY_CHECK_CONSISTENCY -eq 0 ]
then
	wait

	ierules="--exclude="backup""
	
	mkdir -p iso/latest

	log 1 \(II\) syncing iso images...	
	rsync $rsyncopts $ierules $mirror/iso/latest/ iso/latest/ 2>> sync.log 1> /dev/null
	log 1 \(II\) done syncing iso images.

	log 1 \(II\) cleaning up iso images...
	rm -rf iso/latest/backup

	log 1 \(II\) done cleaning up iso images.
fi

wait

error=0
errorold=0
for repo in $repos
do
	for arch in $archs
	do
                if ( [ "$repo" = "multilib" ] || [ "$repo" = "multilib-testing" ] ) && [ "$arch" != "x86_64" ]
                then
                        continue
                fi

		if [ "$arch" = "any" ]
		then
			continue
		fi

		log 1 \(II\) checking consistency of $repo/os/$arch ...

		if ! consistencycheck $repo $arch
		then
			errlog \(WW\) $repo/os/$arch is inconsistent... trying to revert to old db...

			for db in abs db files
			do
				if [ -e $repo/os/$arch/$repo.$db.tar.gz.consistent ]
				then	
					cp $repo/os/$arch/$repo.$db.tar.gz.consistent $repo/os/$arch/$repo.$db.tar.gz
				fi
			done

			cp -r $repo/os/backup/$arch/. $repo/os/$arch/
			cp -r $repo/os/backup/any/. $repo/os/any/


			if ! consistencycheck $repo $arch
			then
				errlog \(EE\) reverting $repo/os/$arch to a consistent state failed
				error=1
			else
				log 1 \(II\) reverting was successful
			fi
		elif [ $ONLY_CHECK_CONSISTENCY -eq 0 ]
		then
			log 1 \(II\) $repo/os/$arch seems to be consistent... cleaning up $repo/os/$arch ...

			rm -rf $repo/os/backup/$arch

			log 1 \(II\) done cleaning up $repo/os/$arch.

			for db in abs db files
			do
				if [ -e $repo/os/$arch/$repo.$db.tar.gz ]
				then
					cp $repo/os/$arch/$repo.$db.tar.gz $repo/os/$arch/$repo.$db.tar.gz.consistent
				fi
			done
		fi
	done

	if [ $error -eq 0 ] && [ $ONLY_CHECK_CONSISTENCY -eq 0 ]
	then
		log 1 \(II\) $repo/os/\* seems to be consistent... cleaning up $repo/os ...
		rm -rf $repo/os/backup
	fi
done

if ! [ $error -eq 0 ]
then
	errlog \(EE\) This mirror has inconsistencies... please try again later!
	log 1 "*** synchronization failed"
else
	log 1 "*** synchronization finished"
fi

exit $error
