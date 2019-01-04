#!/bin/bash

# Updater for NextCloudPi
#
# Copyleft 2017 by Ignacio Nunez Hernanz <nacho _a_t_ ownyourbits _d_o_t_ com>
# GPL licensed (see end of file) * Use at your own risk!
#
# More at https://ownyourbits.com/
#

CONFDIR=/usr/local/etc/ncp-config.d/

# don't make sense in a docker container
EXCL_DOCKER="
nc-automount
nc-format-USB
nc-datadir
nc-database
nc-ramlogs
nc-swapfile
nc-static-IP
nc-wifi
nc-nextcloud
nc-init
UFW
nc-snapshot
nc-snapshot-auto
nc-audit
nc-hdd-monitor
SSH
fail2ban
NFS
"

# better use a designated container
EXCL_DOCKER+="
samba
"

# check running apt
pgrep apt &>/dev/null && { echo "apt is currently running. Try again later";  exit 1; }

## TODO migration - temporary -
# install new dependencies
type jq &>/dev/null || {
  apt-get update
  apt-get install -y --no-install-recommends jq
}

# migrate to the new cfg format
[[ -f "$CONFDIR"/dnsmasq.sh ]] && {

  mv "$CONFDIR"/DDNS_duckDNS.sh "$CONFDIR"/duckDNS.sh
  mv "$CONFDIR"/DDNS_freeDNS.sh "$CONFDIR"/freeDNS.sh
  mv "$CONFDIR"/DDNS_no-ip.sh   "$CONFDIR"/no-ip.sh
  mv "$CONFDIR"/DDNS_spDYN.sh   "$CONFDIR"/spDYN.sh

  for file in "$CONFDIR"/*.sh; do
          test -f $file || continue
          app=$(basename $file .sh)

          unset DESC INFO INFOTITLE cfg vars vals
          source $file

          cfg=$(echo '{}' | jq ".id = \"$app\"")

          cfg=$(jq ".name = \"$app\"" <<<"$cfg")

          cfg=$(jq ".title = \"$app\"" <<<"$cfg")

          cfg=$(jq ".description = \"$DESCRIPTION\"" <<<"$cfg")

          cfg=$(jq ".info = \"$INFO\"" <<<"$cfg")

          cfg=$(jq ".infotitle = \"$INFOTITLE\"" <<<"$cfg")

          cfg=$(jq ".params = []" <<<"$cfg")

          vars=( $( grep "^[[:alpha:]]\+_=" "$file" | cut -d= -f1 | sed 's|_$||' ) )
          vals=( $( grep "^[[:alpha:]]\+_=" "$file" | cut -d= -f2 ) )

          for i in $( seq 0 1 $(( ${#vars[@]} - 1 )) ); do
            cfg=$(jq ".params[$i].id = \"${vars[$i]}\"" <<<"$cfg")
            cfg=$(jq ".params[$i].name = \"${vars[$i]}\"" <<<"$cfg")
            cfg=$(jq ".params[$i].value = \"${vals[$i]}\"" <<<"$cfg")
          done

          echo "$cfg" > "$CONFDIR/$app.cfg"
          rm $file
  done
}
## TODO migration - end -

cp etc/library.sh /usr/local/etc/

source /usr/local/etc/library.sh

mkdir -p "$CONFDIR"

# prevent installing some ncp-apps in the docker version
[[ -f /.docker-image ]] && {
  for opt in $EXCL_DOCKER; do
    touch $CONFDIR/$opt.cfg
  done
}

# copy all files in bin and etc
cp -r bin/* /usr/local/bin/
find etc -maxdepth 1 -type f -exec echo cp '{}' /usr/local/ \;

# install new entries of ncp-config and update others
for file in etc/ncp-config.d/*; do
  [ -f "$file" ] || continue;    # skip dirs
  [ -f /usr/local/"$file" ] || { # new entry
    install_app "$(basename "$file" .cfg)"

    # configure if active by default
    [[ "$(jq -r ".params[0].id"    "$file")" == "active" ]] && \
    [[ "$(jq -r ".params[0].value" "$file")" == "yes"    ]] && \
      run_app_unsafe "$file"
  }
  cp "$file" /usr/local/"$file"
done

# install localization files
cp -rT etc/ncp-config.d/l10n "$CONFDIR"/l10n

# these files can contain sensitive information, such as passwords
chown -R root:www-data "$CONFDIR"
chmod 660 "$CONFDIR"/*
chmod 750 "$CONFDIR"/l10n

# install web interface
cp -r ncp-web /var/www/
chown -R www-data:www-data /var/www/ncp-web
chmod 770                  /var/www/ncp-web

[[ -f /.docker-image ]] && {
  # remove unwanted ncp-apps for the docker version
  for opt in $EXCL_DOCKER; do
    rm $CONFDIR/$opt.cfg
    find /usr/local/bin/ncp -name "$opt.sh" -exec rm '{}' \;
  done

  # update services
  cp docker-common/{lamp/010lamp,nextcloud/020nextcloud,nextcloudpi/000ncp} /etc/services-enabled.d

}

## BACKWARD FIXES ( for older images )

# not for image builds, only live updates
[[ ! -f /.ncp-image ]] && {

  # docker images only
  [[ -f /.docker-image ]] && {
    :
  }

  # for non docker images
  [[ ! -f /.docker-image ]] && {
    :
  }

  # update nc-restore
  install_app nc-backup
  install_app nc-restore

  # update to NC14.0.4
  is_active_app nc-autoupdate-nc && run_app nc-autoupdate-nc

  # remove redundant opcache configuration. Leave until update bug is fixed -> https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=815968
  # Bug #416 reappeared after we moved to php7.2 and debian buster packages. (keep last)
  [[ "$( ls -l /etc/php/7.2/fpm/conf.d/*-opcache.ini |  wc -l )" -gt 1 ]] && rm "$( ls /etc/php/7.2/fpm/conf.d/*-opcache.ini | tail -1 )"
  [[ "$( ls -l /etc/php/7.2/cli/conf.d/*-opcache.ini |  wc -l )" -gt 1 ]] && rm "$( ls /etc/php/7.2/cli/conf.d/*-opcache.ini | tail -1 )"

  # in NC14.0.4 the referrer policy is included in .htaccess
  grep -q Referrer-Policy /var/www/nextcloud/.htaccess && sed -i /Referrer-Policy/d /etc/apache2/apache2.conf

} # end - only live updates

exit 0

# License
#
# This script is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this script; if not, write to the
# Free Software Foundation, Inc., 59 Temple Place, Suite 330,
# Boston, MA  02111-1307  USA

