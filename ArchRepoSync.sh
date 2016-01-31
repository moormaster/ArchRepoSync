#!/bin/bash

#
# ArchRepoSync - (c) 2009 by Andre Herbst, Greifswald
#


function setDefaultConfiguration() {
	#
	# CONFIGURATION
	#
	CONFIG_MIRROR="rsync://mirrors.kernel.org/archlinux"
	CONFIG_TARGETDIR="."

	CONFIG_ACTION="sync"

	CONFIG_REPOS="core extra community multilib"
	CONFIG_TESTINGREPOS="community-testing gnome-unstable kde-unstable multilib-testing testing"
	CONFIG_ARCHS="i686 x86_64"

	CONFIG_INTEGRITY_CHECK=0
	CONFIG_PARALLELDOWNLOADS=4

	CONFIG_VERBOSITY=0
	#
	# END OF CONFIGURATION
	#
}

function setConfiguration() {
	CONFIG_MIRROR=""
	CONFIG_REPOS=""
	CONFIG_ARCHS=""
	CONFIG_INTEGRITY_CHECK=""
	CONFIG_PARALLELDOWNLOADS=""
	CONFIG_TARGETDIR=""
	CONFIG_ACTION=""
	CONFIG_VERBOSITY=""

	local ARG_ARCHS=""
	local ARG_ONLY_CHECK_CONSISTENCY=0
	local ARG_TARGETDIR=""
	local ARG_PRINT_USAGE=0
	local ARG_INTEGRITY_CHECK=0
	local ARG_MIRROR=""
	local ARG_CONFIG_PARALLELDOWNLOADS=""
	local ARG_REPOS=""
	local ARG_ADD_TESTING_REPOS=""
	local ARG_VERBOSITY=0

	setDefaultConfiguration
	parseOpts "$@"
	
	if ! [ "$ARG_ARCHS" = "" ]
	then
		if [ "$ARG_ARCHS" = "none" ]
		then
			CONFIG_ARCHS=""
		else
			CONFIG_ARCHS="$ARG_ARCHS"
		fi
	fi

	if ! echo $CONFIG_ARCHS | grep any && [ "$CONFIG_ARCHS" != "" ]
	then
		CONFIG_ARCHS="any $CONFIG_ARCHS"
	fi

	if ! [ "$ARG_REPOS" = "" ]
	then
		if [ "$ARG_REPOS" = "none" ]
		then
			CONFIG_REPOS=""
		else
			CONFIG_REPOS="$ARG_REPOS"
		fi
	fi

	if [ "$ARG_REPOS" != "none" ]
	then
		if [ "$ARG_ADD_TESTING_REPOS" != "" ] && [ $ARG_ADD_TESTING_REPOS -eq 1 ]
		then
			CONFIG_REPOS="$CONFIG_REPOS $CONFIG_TESTINGREPOS"
		fi
	fi

	if ! [ "$ARG_MIRROR" = "" ]
	then
		CONFIG_MIRROR=$ARG_MIRROR;
	fi

	if ! [ "$ARG_CONFIG_PARALLELDOWNLOADS" = "" ] && [ $ARG_CONFIG_PARALLELDOWNLOADS -gt 0 ]
	then
		CONFIG_PARALLELDOWNLOADS=$ARG_CONFIG_PARALLELDOWNLOADS
	fi

	if [ $ARG_INTEGRITY_CHECK -eq 1 ]
	then
		CONFIG_INTEGRITY_CHECK=1
	fi

	if [ $ARG_ONLY_CHECK_CONSISTENCY -eq 1 ]
	then
		CONFIG_ACTION="check"
	fi

	if [ "$ARG_TARGETDIR" != "" ]
	then
		CONFIG_TARGETDIR="$ARG_TARGETDIR"
	fi

	if [ $ARG_PRINT_USAGE -eq 1 ]
	then
		CONFIG_ACTION="usage"
	fi

	if [ "$ARG_VERBOSITY" != "" ] && [ $ARG_VERBOSITY -ge 0 ]
	then
		CONFIG_VERBOSITY=$ARG_VERBOSITY
	fi
}

function parseOpts() {
	ARG_ARCHS=""
	ARG_ONLY_CHECK_CONSISTENCY=0
	ARG_TARGETDIR=""
	ARG_PRINT_USAGE=0
	ARG_INTEGRITY_CHECK=0
	ARG_MIRROR=""
	ARG_CONFIG_PARALLELDOWNLOADS=""
	ARG_REPOS=""
	ARG_ADD_TESTING_REPOS=0
	ARG_VERBOSITY=0

	local opt=!
	local OPTARG

	while ! [ "$opt" = "?" ]
	do
		getopts a:cd:him:p:r:tv opt $*

		case $opt in
			a)
				ARG_ARCHS="$ARG_ARCHS $OPTARG";;
			c)
				ARG_ONLY_CHECK_CONSISTENCY=1;;
			d)
				ARG_TARGETDIR="$OPTARG";;
			h)
				ARG_PRINT_USAGE=1;;
			i)
				ARG_INTEGRITY_CHECK=1;;
			m)
				ARG_MIRROR=$OPTARG;;
			p)
				ARG_CONFIG_PARALLELDOWNLOADS=$OPTARG;;
			r)
				ARG_REPOS="$ARG_REPOS $OPTARG";;
			t)
				ARG_ADD_TESTING_REPOS=1;;
			v)
				ARG_VERBOSITY=$(( $ARG_VERBOSITY + 1));;
		esac
	done
}

function usage() {
	echo "usage: $( basename "$0" ) [-chiv] [-a <arch>] [-r <repo>] [-m <mirror>] [-p <num parallel processes>]"
	echo "options:"
	echo " -a <arch>	select arch; i.e. one of {i686, x86_64, none}"
	echo "			to specify multiple values you need to add the parameter multiple times"
	echo "			default: -a i686 -a x86_86"
	echo ""
	echo " -r <repo>	select repo; i.e. one of {core, extra, community, none}"
	echo "			to specify multiple values you need to add the parameter multiple times"
	echo "			default: -r core -r extra -r community -r multilib"
	echo ""
	echo " -c		only check consistency"
	echo " -d <directory>	target directory (default: \".\")"
	echo " -h		show help"
	echo " -i		do md5 integrity check"
	echo " -m <mirror>	use specified mirror"
	echo " -p <num>		use num parallel rsync instances"
	echo " -t		add all testing repos"
	echo " -v		verbose"
	echo
	echo "example:	$( basename "$0" ) -v -a i686 -r core -r extra -r community"
	echo "		download core,extra,community repos for i686 architecture"
	echo
}

log()
{
	verbositylvl=$1
	shift 1

	if [ $CONFIG_VERBOSITY -ge $verbositylvl ]
	then
		echo "$*" | tee -a "$CONFIG_TARGETDIR/sync.log"
	else
		echo "$*" >> "$CONFIG_TARGETDIR/sync.log"
	fi
}

errlog()
{
	echo "$*" >> "$CONFIG_TARGETDIR/sync.log"
	echo "$*" 1>&2
}

repo-readdescs() {
	local targetdir=$1
	local repo=$2
	local arch=$3

	DBFILE="$targetdir/$repo/os/$arch/$repo.db.tar.gz"

	if [ "$arch" = "any" ]
	then
		return 1
	fi

	if ! [ -e "$DBFILE" ]
	then
		errlog \(EE\) $DBFILE not found	
		return 1
	fi

	tar -xzOf "$DBFILE" --wildcards */desc	
}

repo-readmd5sums() {
	local targetdir=$1
	local repo=$2
	local arch=$3

	repo-readdescs "$targetdir" "$repo" "$arch" | 
	(
		error=0
		lastline=""

		filename=""
		md5sum=""

		line=""

		while read line
		do
			if [ "$lastline" == "%FILENAME%" ]
			then
				filename="$line"
			elif [ "$lastline" == "%MD5SUM%" ]
			then
				md5sum=$line
				echo "$md5sum $filename"
			fi

			lastline="$line"
		done

		return $error
	)

}

config-getarchs() {
	local repo="$1"
	local arch

	for arch in $CONFIG_ARCHS
	do
		# multilib uses 64 bit arch only -> skip all other architectures for this
		if ( [ "$repo" = "multilib" ] || [ "$repo" = "multilib-testing" ] ) && [ "$arch" != "x86_64" ]
		then
			continue
		fi

		echo "$arch"
	done
}

repo-getarchdirs() {
	local repo="$1"

	local arch=""

	config-getarchs "$repo" | while read arch
	do
		echo "$repo/os/$arch"
	done
}

repo-mkdirtargetarchdirs() {
	local targetdir="$1"
	local repo="$2"

	local arch=""

	config-getarchs "$repo" | while read arch
	do
		mkdir -p "$targetdir/$repo/os/$arch"
	done
}

repo-getrsyncierules() {
	local repo="$1"

	local arch=""

	config-getarchs "$repo" | while read arch
	do
		echo -n " --include="$arch" --include="$arch/**""
	done
	echo " --exclude="*""
}

repo-restoreconsistentcontrolfiles() {
	local targetdir="$1"
	local repo="$2"

	local arch=""

	config-getarchs "$repo" | while read arch
	do
		if [ "$arch" = "any" ]
		then
			continue;
		fi

		for db in abs db files
		do
			if [ -e "$targetdir/$repo/os/backup/$arch/$repo.$db.tar.gz.consistent" ]
			then
				mv "$targetdir/$repo/os/backup/$arch/$repo.$db.tar.gz.consistent" "$targetdir/$repo/os/$arch/"
			fi
		done
	done
}


repo-consistencycheck()
{
	local targetdir=$1
	local repo=$2
	local arch=$3
	local domd5sum=$4

	if ! [ "$arch" = "any" ]
	then
		repo-readmd5sums "$targetdir" "$repo" "$arch" | 
		(
			error=0

			filename=""
			md5sum=""

			while read md5sum filename
			do
				if [ -L "$targetdir/$repo/os/$arch/$filename" ] && ! [ -e "$targetdir/$repo/os/any/$filename" ]
				then
					errlog \(EE\) missing package: $repo/os/any/$filename
					error=1
				fi

				if ! [ -e "$targetdir/$repo/os/$arch/$filename" ]
				then
					errlog \(EE\) missing package: $repo/os/$arch/$filename
					error=1
				fi
				
				if [ $domd5sum -eq 1 ] && ( echo "$md5sum  $targetdir/$repo/os/$arch/$filename" | md5sum -c --quiet; [ $? -eq 1 ] )
				then
					errlog \(EE\) md5sum corruption of package: $repo/os/$arch/$filename ... deleting file

					if ! [ -e "$targetdir/$repo/os/$arch/$filename" ] || [ -L "$targetdir/$repo/os/$arch/$filename" ]
					then
						rm "$targetdir/$repo/os/any/$filename"
					else
						rm "$targetdir/$repo/os/$arch/$filename"
					fi
					error=1
				fi
			done

			return $error
		)
	fi

	return $?
}

sync-packagesparallel() {
	local mirror="$1"
	local targetdir="$2"
	local paralleldownloads="$3"
	local repos="$4"

	local rsyncopts="-abv --copy-unsafe-links --no-motd --delete --ignore-errors --backup-dir=backup"

	local dcount=0
	for repo in $repos
	do
		local ierules="$( repo-getrsyncierules "$repo" )"

		(
			log 1 \(II\) syncing $repo/os ...

			rsync $rsyncopts $ierules "$mirror/$repo/os/" "$targetdir/$repo/os/" 2>> "$targetdir/sync.log" 1> /dev/null
			repo-restoreconsistentcontrolfiles "$targetdir" "$repo"

			log 1 \(II\) done syncing $repo/os.
		) &

		dcount=$(( $dcount + 1))

		if [ $dcount -ge $paralleldownloads ]
		then
			wait
			dcount=0
		fi
	done

	wait
}

sync-iso() {
	local mirror="$1"
	local targetdir="$2"

	local ierules="--exclude="backup""
	
	mkdir -p "$targetdir/iso/latest"

	log 1 \(II\) syncing iso images...	
	rsync $rsyncopts $ierules "$mirror/iso/latest/" "$targetdir/iso/latest/" 2>> "$targetdir/sync.log" 1> /dev/null
	log 1 \(II\) done syncing iso images.

	log 1 \(II\) cleaning up iso images...
	rm -rf "$targetdir/iso/latest/backup"

	log 1 \(II\) done cleaning up iso images.
}

sync-getrepoarchconsistency() {
	local targetdir="$1"
	local repos="$2"
	local integritycheck="$3"

	local arch=""

	local error=0
	for repo in $repos
	do
		local repoerror=0

		config-getarchs "$repo" | while read arch
		do
			if [ "$arch" = "any" ]
			then
				continue
			fi
	
			if repo-consistencycheck "$targetdir" $repo $arch $integritycheck
			then
				# repo arch is consistent
				echo "1 $repo $arch"
			else
				# repo arch is inconsistent
				echo "0 $repo $arch" 
				repoerror=1
			fi
		done
	
		if [ $repoerror -eq 0 ]
		then
			# repo is consistent
			echo "1 $repo"
		else
			# repo is inconsistent
			echo "0 $repo"
			error=1
		fi
	done

	if [ $error -eq 0 ]
	then
		return 1	# failure
	else
		return 0	# success
	fi
}

setConfiguration "$@"

if [ "$CONFIG_ACTION" = "usage" ]
then
	usage
	exit 0
fi

if [ "$CONFIG_ACTION" = "check" ]
then
	log 1 "*** only checking consistency: $(date)"
else
	log 1 "*** synchronization started: $(date)"
	log 1 \(II\) using mirror $CONFIG_MIRROR
	log 1 \(II\) using $CONFIG_PARALLELDOWNLOADS parallel rsync instances
	log 1 \(II\) repos: $CONFIG_REPOS
	log 1 \(II\) archs: $CONFIG_ARCHS
fi


# prepare target directories
for repo in $CONFIG_REPOS
do
	repo-mkdirtargetarchdirs "$CONFIG_TARGETDIR" "$repo"
done

if [ "$CONFIG_ACTION" = "sync" ]
then
	# package sync
	sync-packagesparallel "$CONFIG_MIRROR" "$CONFIG_TARGETDIR" "$CONFIG_PARALLELDOWNLOADS" "$CONFIG_REPOS"

	# iso sync
	sync-iso "$CONFIG_MIRROR" "$CONFIG_TARGETDIR"
fi

error=0
sync-getrepoarchconsistency "$CONFIG_TARGETDIR" "$CONFIG_REPOS" "$CONFIG_INTEGRITY_CHECK" | while read isconsistent repo arch
do
	if [ "$isconsistent" = "" ]
	then
		continue
	fi

	if [ "$arch" != "" ]
	then
		if ! [ $isconsistent -eq 1 ]
		then
			errlog \(WW\) $repo/os/$arch is inconsistent... trying to revert to old db...

			for db in abs db files
			do
				if [ -e "$CONFIG_TARGETDIR/$repo/os/$arch/$repo.$db.tar.gz.consistent" ]
				then	
					cp "$CONFIG_TARGETDIR/$repo/os/$arch/$repo.$db.tar.gz.consistent" "$CONFIG_TARGETDIR/$repo/os/$arch/$repo.$db.tar.gz"
				fi
			done

			cp -r "$CONFIG_TARGETDIR/$repo/os/backup/$arch/." "$CONFIG_TARGETDIR/$repo/os/$arch/"
			cp -r "$CONFIG_TARGETDIR/$repo/os/backup/any/." "$CONFIG_TARGETDIR/$repo/os/any/"

			if ! repo-consistencycheck "$CONFIG_TARGETDIR" $repo $arch $CONFIG_INTEGRITY_CHECK
			then
				errlog \(EE\) reverting $repo/os/$arch to a consistent state failed
				error=1
			else
				log 1 \(II\) reverting was successful
			fi
		else
			log 1 \(II\) $repo/os/$arch seems to be consistent

			if [ "$CONFIG_ACTION" = "sync" ]
			then
				log 1 \(II\) cleaning up $repo/os/$arch ...

				rm -rf "$CONFIG_TARGETDIR/$repo/os/backup/$arch"

				log 1 \(II\) done cleaning up $repo/os/$arch.

				for db in abs db files
				do
					if [ -e "$CONFIG_TARGETDIR/$repo/os/$arch/$repo.$db.tar.gz" ]
					then
						cp "$CONFIG_TARGETDIR/$repo/os/$arch/$repo.$db.tar.gz" "$CONFIG_TARGETDIR/$repo/os/$arch/$repo.$db.tar.gz.consistent"
					fi
				done
			fi
		fi
	else
		if [ $isconsistent -eq 1 ]
		then
			log 1 \(II\) $repo/os/\* seems to be consistent

			if [ "$CONFIG_ACTION" = "sync" ]
			then
				log 1 \(II\) cleaning up $repo/os ...
				rm -rf "$CONFIG_TARGETDIR/$repo/os/backup"
			fi
		else
			error=1
		fi
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
