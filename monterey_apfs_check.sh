#!/bin/bash
# Read-only APFS volume and filesystem diagnostics for macOS Monterey Recovery.
# This script does NOT change MDM enrollment, user accounts, system files, or disks.

set -u

volume_root="/Volumes"
if [ "$#" -gt 0 ]; then
  if [ "$#" -eq 2 ] && [ "$1" = "--volumes-root" ]; then
    volume_root="$2"
  else
    printf 'Usage: bash %s [--volumes-root DIRECTORY]\n' "$0" >&2
    exit 2
  fi
fi

if [ ! -d "$volume_root" ]; then
  printf 'ERROR: Volume directory does not exist: %s\n' "$volume_root" >&2
  exit 2
fi

printf 'macOS Monterey APFS Check (read-only)\n'
printf '====================================\n'
printf 'Mounted volume directories:\n'

any_volume=0
for volume in "$volume_root"/*; do
  [ -d "$volume" ] || continue
  any_volume=1
  printf '  - %s\n' "${volume##*/}"
done

if [ "$any_volume" -eq 0 ]; then
  printf 'ERROR: No mounted volumes found. In Recovery, check Disk Utility > Mount.\n'
  exit 1
fi

system_volume=""
system_fallback=""
for volume in "$volume_root"/*; do
  [ -d "$volume" ] || continue
  name="${volume##*/}"
  case "$name" in
    'macOS Base System'|'OS X Base System'|*' - Data'|'Data'|'Preboot'|'Recovery'|'VM'|'Update')
      continue
      ;;
  esac
  [ -d "$volume/System" ] || continue
  if [ -f "$volume/System/Library/CoreServices/SystemVersion.plist" ]; then
    system_volume="$volume"
    break
  fi
  if [ -z "$system_fallback" ]; then
    system_fallback="$volume"
  fi
done

if [ -z "$system_volume" ]; then
  system_volume="$system_fallback"
fi

data_volume=""
if [ -n "$system_volume" ] && [ -d "$system_volume - Data" ]; then
  data_volume="$system_volume - Data"
elif [ -d "$volume_root/Data" ]; then
  data_volume="$volume_root/Data"
else
  for volume in "$volume_root"/*; do
    [ -d "$volume" ] || continue
    name="${volume##*/}"
    case "$name" in
      *' - Data')
        data_volume="$volume"
        break
        ;;
    esac
  done
fi

printf '\nDetected paths:\n'
if [ -n "$system_volume" ]; then
  printf '  System: %s\n' "$system_volume"
else
  printf '  System: NOT FOUND\n'
fi
if [ -n "$data_volume" ]; then
  printf '  Data:   %s\n' "$data_volume"
else
  printf '  Data:   NOT FOUND\n'
fi

printf '\nPath checks:\n'
status=0
if [ -n "$system_volume" ] && [ -d "$system_volume/System" ]; then
  printf '  [OK] macOS system directory exists\n'
else
  printf '  [FAIL] macOS system directory was not found\n'
  status=1
fi

if [ -n "$data_volume" ]; then
  dscl_path="$data_volume/private/var/db/dslocal/nodes/Default"
  if [ -d "$dscl_path" ]; then
    printf '  [OK] Directory Services database exists\n'
  else
    printf '  [NOTICE] Directory Services database not present at:\n'
    printf '           %s\n' "$dscl_path"
    printf '           This can occur before initial user setup is completed.\n'
    status=1
  fi
else
  printf '  [FAIL] Cannot check Directory Services without a mounted data volume\n'
  status=1
fi

if [ -n "$system_volume" ] && [ -f "$system_volume/System/Library/CoreServices/SystemVersion.plist" ] && [ -x /usr/libexec/PlistBuddy ]; then
  version=$(/usr/libexec/PlistBuddy -c 'Print :ProductVersion' "$system_volume/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null || true)
  if [ -n "$version" ]; then
    printf '\nInstalled macOS version: %s\n' "$version"
  fi
fi

printf '\nSummary:\n'
if [ "$status" -eq 0 ]; then
  printf '  Both APFS volumes and expected folders are present.\n'
else
  printf '  One or more expected paths are absent. No changes were made.\n'
fi
printf '  This tool checks disks only. It does not remove or bypass MDM.\n'

exit "$status"
