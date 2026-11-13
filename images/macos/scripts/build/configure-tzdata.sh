#!/bin/bash -e -o pipefail
################################################################################
##  File:  configure-tzdata.sh
##  Desc:  Make sure the image uses the latest downloaded time zone data
##         instead of the copy bundled with the OS
################################################################################

# macOS ships an old tzdata copy in /usr/share/zoneinfo.default and downloads
# newer data as a background asset into /var/db/timezone/tz/<version>.
# The download can land after the last reboot of the build, or not at all,
# and tzd does not switch /var/db/timezone/zoneinfo to it until later.
# https://github.com/actions/runner-images/issues/14908

tz_root="/var/db/timezone"
timeout_seconds=1200

echo "Bundled tzdata version: $(cat /usr/share/zoneinfo.default/+VERSION)"
echo "Active tzdata version: $(cat /usr/share/zoneinfo/+VERSION)"

echo "Waiting for the time zone data asset to be downloaded..."
elapsed=0
until [[ -d "$tz_root/tz_latest/zoneinfo" ]]; do
    if [[ $elapsed -ge $timeout_seconds ]]; then
        echo "Time zone data asset was not downloaded after ${timeout_seconds} seconds"
        exit 1
    fi
    sleep 30
    elapsed=$((elapsed + 30))
done

latest_dir=$(readlink "$tz_root/tz_latest")
echo "Downloaded tzdata: $latest_dir ($(cat "$latest_dir/zoneinfo/+VERSION"))"

if [[ "$(readlink "$tz_root/zoneinfo")" != "$latest_dir/zoneinfo" ]]; then
    echo "Switching $tz_root/zoneinfo to $latest_dir/zoneinfo"
    ln -sfn "$latest_dir/zoneinfo" "$tz_root/zoneinfo"
fi

if [[ -d "$latest_dir/icutz" && "$(readlink "$tz_root/icutz")" != "$latest_dir/icutz" ]]; then
    echo "Switching $tz_root/icutz to $latest_dir/icutz"
    ln -sfn "$latest_dir/icutz" "$tz_root/icutz"
fi

echo "Active tzdata version: $(cat /usr/share/zoneinfo/+VERSION)"
