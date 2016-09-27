#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Compiles a list of ad-serving domains by downloading them from multiple sources
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Run this script as root or under sudo
echo ":::"

if [[ $EUID -eq 0 ]];then
	echo "::: You are root."
else
	echo "::: sudo will be used."
	# Check if it is actually installed
	# If it isn't, exit because the install cannot complete
	if [ -x "$(command -v sudo)" ];then
		export SUDO="sudo"
	else
		echo "::: Please install sudo or run this script as root."
		exit 1
	fi
fi

function helpFunc()
{
	echo "::: Pull in domains from adlists"
	echo ":::"
	echo "::: Usage: pihole -g"
	echo ":::"
	echo "::: Options:"
	echo ":::  -f, --force				Force lists to be downloaded, even if they don't need updating."
	echo ":::  -h, --help				Show this help dialog"
	exit 1
}


adListFile=/etc/pihole/adlists.list
adListDefault=/etc/pihole/adlists.default
whitelistScript=/opt/pihole/whitelist.sh
blacklistScript=/opt/pihole/blacklist.sh

whitelistFile=/etc/pihole/whitelist.txt
whitelistFileWild=/etc/pihole/whitelist_wildcards.txt
blacklistFile=/etc/pihole/blacklist.txt
blacklistFileWild=/etc/pihole/blacklist_wildcards.txt


#Source the setupVars from install script for the IP
. /etc/pihole/setupVars.conf
#Remove the /* from the end of the IPv4addr.
IPv4addr=${IPv4addr%/*}

# Variables for various stages of downloading and formatting the list
basename=pihole
piholeDir=/etc/${basename}
adList=${piholeDir}/gravity.list
justDomainsExtension=domains
matterAndLight=${basename}.0.matterandlight.txt
supernova=${basename}.1.supernova.txt
eventHorizon=${basename}.2.eventHorizon.txt
accretionDisc=${basename}.3.accretionDisc.txt

###########################
# collapse - begin formation of pihole
function gravity_collapse() {
	echo "::: Neutrino emissions detected..."
	echo ":::"
	#Decide if we're using a custom ad block list, or defaults.
	if [ -f ${adListFile} ]; then
		#custom file found, use this instead of default
		echo -n "::: Custom adList file detected. Reading..."
		sources=()
		while read -r line; do
			#Do not read commented out or blank lines
			if [[ ${line} = \#* ]] || [[ ! ${line} ]]; then
				echo "" > /dev/null
			else
				sources+=(${line})
			fi
		done < ${adListFile}
		echo " done!"
	else
		#no custom file found, use defaults!
		echo -n "::: No custom adlist file detected, reading from default file..."
		sources=()
		while read -r line; do
			#Do not read commented out or blank lines
			if [[ ${line} = \#* ]] || [[ ! ${line} ]]; then
				echo "" > /dev/null
			else
				sources+=(${line})
			fi
		done < ${adListDefault}
		echo " done!"
	fi

	# Create the pihole resource directory if it doesn't exist.  Future files will be stored here
	if [[ -d ${piholeDir} ]];then
        # Temporary hack to allow non-root access to pihole directory
        # Will update later, needed for existing installs, new installs should
        # create this directory as non-root
        ${SUDO} chmod 777 ${piholeDir}
        echo ":::"
        echo "::: Existing pihole directory found"
	else
        echo "::: Creating pihole directory..."
        mkdir ${piholeDir}
        ${SUDO} chmod 777 ${piholeDir}
	fi
}

# patternCheck - check to see if curl downloaded any new files.
function gravity_patternCheck() {
	patternBuffer=$1
	# check if the patternbuffer is a non-zero length file
	if [[ -s "$patternBuffer" ]];then
		# Some of the blocklists are copyright, they need to be downloaded
		# and stored as is. They can be processed for content after they
		# have been saved.
		cp "$patternBuffer" "$saveLocation"
		echo " List updated, transport successful!"
	else
		# curl didn't download any host files, probably because of the date check
		echo " No changes detected, transport skipped!"
	fi
}

# transport - curl the specified url with any needed command extentions
function gravity_transport() {
	url=$1
	cmd_ext=$2
	agent=$3

	# tmp file, so we don't have to store the (long!) lists in RAM
	patternBuffer=$(mktemp)
	heisenbergCompensator=""
	if [[ -r ${saveLocation} ]]; then
		# if domain has been saved, add file for date check to only download newer
		heisenbergCompensator="-z $saveLocation"
	fi

	# Silently curl url
	curl -s -L ${cmd_ext} ${heisenbergCompensator} -A "$agent" ${url} > ${patternBuffer}
	# Check for list updates
	gravity_patternCheck "$patternBuffer"
	# Cleanup
	rm -f "$patternBuffer"
}

# spinup - main gravity function
function gravity_spinup() {
	echo ":::"
	# Loop through domain list.  Download each one and remove commented lines (lines beginning with '# 'or '/') and	 		# blank lines
	for ((i = 0; i < "${#sources[@]}"; i++))
	do
        url=${sources[$i]}
        # Get just the domain from the URL
        domain=$(echo "$url" | cut -d'/' -f3)

        # Save the file as list.#.domain
        saveLocation=${piholeDir}/list.${i}.${domain}.${justDomainsExtension}
        activeDomains[$i]=${saveLocation}

        agent="Mozilla/10.0"

        echo -n "::: Getting $domain list..."

        # Use a case statement to download lists that need special cURL commands
        # to complete properly and reset the user agent when required
        case "$domain" in
            "adblock.mahakala.is")
                agent='Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36'
                cmd_ext="-e http://forum.xda-developers.com/"
            ;;

            "pgl.yoyo.org")
                cmd_ext="-d mimetype=plaintext -d hostformat=hosts"
            ;;

            # Default is a simple request
            *) cmd_ext=""
        esac
        gravity_transport "$url" "$cmd_ext" "$agent"
	done
}

# Schwarzchild - aggregate domains to one list and add blacklisted domains
function gravity_Schwarzchild() {
	echo "::: "
	# Find all active domains and compile them into one file and remove CRs
	echo -n "::: Aggregating list of domains..."
	truncate -s 0 ${piholeDir}/${matterAndLight}
	for i in "${activeDomains[@]}"
	do
		cat "$i" | tr -d '\r' >> ${piholeDir}/${matterAndLight}
	done
	echo " done!"
}

function gravity_Blacklist(){
	# Append blacklist entries if they exist
	echo -n "::: Running blacklist script to update HOSTS file...."
	${blacklistScript} -f -nr -q > /dev/null

	numBlacklisted=$(wc -l < "/etc/pihole/blacklist.txt")
	plural=; [[ "$numBlacklisted" != "1" ]] && plural=s
	echo " $numBlacklisted domain${plural} blacklisted!"
}

function gravity_Whitelist() {
	echo ":::"
	# Prevent our sources from being pulled into the hole
	plural=; [[ "${sources[@]}" != "1" ]] && plural=s
	echo -n "::: Adding ${#sources[@]} adlist source${plural} to the whitelist..."

	urls=()
	for url in "${sources[@]}"
	do
        tmp=$(echo "$url" | awk -F '/' '{print $3}')
        urls=("${urls[@]}" ${tmp})
	done
	echo " done!"

	echo -n "::: Running whitelist script to update HOSTS file...."
	${whitelistScript} -f -nr -q "${urls[@]}" > /dev/null
	numWhitelisted=$(wc -l < "/etc/pihole/whitelist.txt")
	plural=; [[ "$numWhitelisted" != "1" ]] && plural=s
	echo " $numWhitelisted domain${plural} whitelisted!"
}

function gravity_prepare() {
    #clear out exception file
    local exceptionFile=/etc/dnsmasq.d/02-exceptions.conf
    if [ -f ${exceptionFile} ]; then
        ${SUDO} echo "#File Automatically Generated by gravity.sh. Manual changes will be overwritten at any time" > ${exceptionFile}
    else
        ${SUDO} touch ${exceptionFile}
        ${SUDO} echo "#File Automatically Generated by gravity.sh. Manual changes will be overwritten at any time" > ${exceptionFile}
    fi

    #inject custom blacklist domains into the supernova
    if [ -f ${blacklistFile} ]; then
        numberOf=$(wc -l < ${blacklistFile})
        echo -n "::: Adding $numberOf custom blacklist domains..."
        while read -r LINE
          do
            echo ${LINE} >> ${piholeDir}/${supernova}
          done < ${blacklistFile}
        echo " done!"
    fi

    # Remove whitelist domains from the supernova
    if [ -f ${whitelistFile} ]; then
        numberOf=$(wc -l < ${whitelistFile})
        echo -n "::: Removing $numberOf whitelisted domains..."
        ${SUDO} echo "#Whitelist Exceptions:" >> ${exceptionFile}
        while read -r LINE
          do
            sed -r -i "s/$LINE.*?$//g" "${piholeDir}/${supernova}"
             #add to exception file to make sure they over-ride blacklist wildcards
             ${SUDO} echo "server=/$LINE/#" >> ${exceptionFile}
          done < ${whitelistFile}
        echo " done!"
    fi

    # Remove whitelist wildcards from the supernova
    if [ -f ${whitelistFileWild} ]; then
        numberOf=$(wc -l < ${whitelistFileWild})
        countBefore=$(wc -l < ${piholeDir}/${supernova})
        echo -n "::: Applying $numberOf whitelist wildcard rules..."
        while read -r LINE
          do
            sed -r -i "s/.*$LINE.*?$//g" "${piholeDir}/${supernova}" && sed -r -i '/^\s*$/d' "${piholeDir}/${supernova}"
            ${SUDO} echo "server=/$LINE/#" >> ${exceptionFile}
          done < ${whitelistFileWild}
        echo " done!"
        countAfter=$(wc -l < ${piholeDir}/${supernova})
        echo "::: Whitelisted `expr ${countBefore} - ${countAfter}` domains using wildcards"
    fi

    # Add blacklist wildcards to exception file
    if [ -f ${blacklistFileWild} ]; then
        numberOf=$(wc -l < ${blacklistFileWild})
        echo -n "::: Adding $numberOf custom blacklist wildcard  domains..."
        ${SUDO} echo "#Blacklist wildcards:" >> ${exceptionFile}
        while read -r LINE
          do
            ${SUDO} echo "address=/$LINE/$IPv4addr" >> ${exceptionFile}
            if [[ -n ${piholeIPv6} ]];then
                ${SUDO} echo "address=/$LINE/$piholeIPv6" >> ${exceptionFile}
            fi
          done < ${blacklistFileWild}
        echo " done!"
    fi

	# Sort and remove duplicates
	echo -n "::: Removing duplicate domains...."
	sort -u  ${piholeDir}/${supernova} > ${piholeDir}/${eventHorizon}
	echo " done!"
	numberOf=$(wc -l < ${piholeDir}/${eventHorizon})
	echo "::: $numberOf unique domains trapped in the event horizon."
}

function gravity_hostFormat() {
	# Format domain list as "192.168.x.x domain.com"
	echo "::: Formatting domains into a HOSTS file..."
	if [[ -f /etc/hostname ]]; then
		hostname=$(</etc/hostname)
	elif [ -x "$(command -v hostname)" ]; then
		hostname=$(hostname -f)
	else
		echo "::: Error: Unable to determine fully qualified domain name of host"
	fi
	# If there is a value in the $piholeIPv6, then IPv6 will be used, so the awk command modified to create a line for both protocols
	if [[ -n ${piholeIPv6} ]];then
		# Add hostname and dummy domain to the top of gravity.list to make ping result return a friendlier looking domain! Also allows for an easy way to access the Pi-hole admin console (pi.hole/admin)
		echo -e "$IPv4addr $hostname\n$piholeIPv6 $hostname\n$IPv4addr pi.hole\n$piholeIPv6 pi.hole" > ${piholeDir}/${accretionDisc}
		cat ${piholeDir}/${eventHorizon} | awk -v ipv4addr="$IPv4addr" -v ipv6addr="$piholeIPv6" '{sub(/\r$/,""); print ipv4addr" "$0"\n"ipv6addr" "$0}' >> ${piholeDir}/${accretionDisc}
	else
		# Otherwise, just create gravity.list as normal using IPv4
		# Add hostname and dummy domain to the top of gravity.list to make ping result return a friendlier looking domain! Also allows for an easy way to access the Pi-hole admin console (pi.hole/admin)
		echo -e "$IPv4addr $hostname\n$IPv4addr pi.hole" > ${piholeDir}/${accretionDisc}
		cat ${piholeDir}/${eventHorizon} | awk -v ipv4addr="$IPv4addr" '{sub(/\r$/,""); print ipv4addr" "$0}' >> ${piholeDir}/${accretionDisc}
	fi

	# Copy the file over as /etc/pihole/gravity.list so dnsmasq can use it
	cp ${piholeDir}/${accretionDisc} ${adList}
}

# blackbody - remove any remnant files from script processes
function gravity_blackbody() {
	# Loop through list files
	for file in ${piholeDir}/*.${justDomainsExtension}
	do
		# If list is in active array then leave it (noop) else rm the list
		if [[ " ${activeDomains[@]} " =~ ${file} ]]; then
			:
		else
			rm -f "$file"
		fi
	done
}

function gravity_advanced() {
	# Remove comments and print only the domain name
	# Most of the lists downloaded are already in hosts file format but the spacing/formating is not contigious
	# This helps with that and makes it easier to read
	# It also helps with debugging so each stage of the script can be researched more in depth
	echo -n "::: Formatting list of domains to remove comments...."
	awk '($1 !~ /^#/) { if (NF>1) {print $2} else {print $1}}' ${piholeDir}/${matterAndLight} | sed -nr -e 's/\.{2,}/./g' -e '/\./p' >  ${piholeDir}/${supernova}
	echo " done!"

	numberOf=$(wc -l < ${piholeDir}/${supernova})
	echo "::: $numberOf domains being pulled in by gravity..."

	gravity_prepare
}

function gravity_reload() {
	#Clear no longer needed files...
	echo ":::"
	echo -n "::: Cleaning up un-needed files..."
	${SUDO} rm ${piholeDir}/pihole.*.txt
	echo " done!"

	# Reload hosts file
	echo ":::"
	echo -n "::: Refresh lists in dnsmasq..."
	
	#ensure /etc/dnsmasq.d/01-pihole.conf is pointing at the correct list!
	#First escape forward slashes in the path:
	adList=${adList//\//\\\/}
	#Now replace the line in dnsmasq file
	${SUDO} sed -i "s/^addn-hosts.*/addn-hosts=$adList/" /etc/dnsmasq.d/01-pihole.conf
	dnsmasqPid=$(pidof dnsmasq)

    find "$piholeDir" -type f -exec ${SUDO} chmod 666 {} \;

	if [[ ${dnsmasqPid} ]]; then
		# service already running - reload config
		${SUDO} service dnsmasq reload
		${SUDO} service dnsmasq restart
	else
		# service not running, start it up
		${SUDO} service dnsmasq start
	fi
	echo " done!"
}


for var in "$@"
do
  case "$var" in
    "-f" | "--force"     ) forceGrav=true;;
    "-h" | "--help"      ) helpFunc;;
  esac
done

if [[ ${forceGrav} == true ]]; then
	echo -n "::: Deleting exising list cache..."
	${SUDO} rm /etc/pihole/list.*
	echo " done!"
fi

#Overwrite adlists.default from /etc/.pihole in case any changes have been made. Changes should be saved in /etc/adlists.list
${SUDO} cp /etc/.pihole/adlists.default /etc/pihole/adlists.default
gravity_collapse
gravity_spinup
gravity_Schwarzchild
gravity_advanced
gravity_hostFormat
gravity_blackbody
#gravity_Whitelist
#gravity_Blacklist
gravity_reload
