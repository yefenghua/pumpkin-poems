#!/bin/bash
# Build and launch a repeatable iPhone demo without erasing saved learning or poems.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: demo.sh cantonese|mandarin [--route ROUTE] [--tab today|library|me]
               [--device SIMULATOR_UDID] [--seed] [--no-build]

  cantonese   Traditional Chinese + Cantonese read-aloud
  mandarin    Simplified Chinese + Mandarin read-aloud
  --route     poem:hk-ks1-10, recite:hk-ks1-10, quiz:hk-ks1-10,
              games, feihualing:月, versegrid, wordle,
              review, theme:moon, workshop, mypoems,
              mistakes, settings (omit to open the home screen)
  --seed      Add sample progress only when the app's seed guard allows it
  --no-build  Reuse the previous Debug build in PUMPKIN_DEMO_BUILD_DIR

Uses an already booted standard iPhone, otherwise the first available standard iPhone.
iPhone Duo is excluded from automatic device selection.
Every launch resets the simulated date to today; saved records are retained.
Set DEVELOPER_DIR for a custom Xcode installation. No global setting is changed.
HELP
}

if [[ $# == 0 || ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi
language=$1
shift
case "$language" in cantonese|mandarin) ;; *) usage >&2; exit 2 ;; esac
route=""
tab=today
device=""
seed=NO
build=YES
while [[ $# -gt 0 ]]; do
  case "$1" in
    --route|--tab|--device)
      [[ $# -ge 2 && -n $2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in --route) route=$2 ;; --tab) tab=$2 ;; --device) device=$2 ;; esac
      shift 2 ;;
    --seed) seed=YES; shift ;;
    --no-build) build=NO; shift ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$tab" in today|library|me) ;; *) echo "Invalid tab: $tab" >&2; exit 2 ;; esac

APP="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z ${DEVELOPER_DIR:-} && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
build_dir=${PUMPKIN_DEMO_BUILD_DIR:-${TMPDIR:-/tmp}/pumpkin-poems-demo-build}
bundle_id=com.fredrickyepersonalteam.pumpkinpoemsapp
app_bundle="$build_dir/Build/Products/Debug-iphonesimulator/pumpkin-poems-app.app"
mkdir -p "$build_dir"

if [[ -z $device ]]; then
  device=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group
           if d.get("isAvailable") and d["name"].startswith("iPhone") and "Duo" not in d["name"]]
devices.sort(key=lambda d: d["state"] != "Booted")
if not devices:
    sys.exit("No available standard iPhone simulator. Create a regular iPhone device in Xcode; iPhone Duo is not used for this demo.")
print(devices[0]["udid"])
')
fi

if [[ $build == YES ]]; then
  echo "Building Pumpkin Poems…"
  if ! xcodebuild -project "$APP/pumpkin-poems-app.xcodeproj" \
       -scheme pumpkin-poems-app -configuration Debug -sdk iphonesimulator \
       -destination "id=$device" -derivedDataPath "$build_dir" \
       CODE_SIGNING_ALLOWED=NO build > "$build_dir/build.log" 2>&1; then
    tail -80 "$build_dir/build.log" >&2
    echo "Full build log: $build_dir/build.log" >&2
    exit 1
  fi
fi
[[ -d $app_bundle ]] || { echo "No Debug build at $app_bundle. Run without --no-build." >&2; exit 1; }

state=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
device_id = sys.argv[1]
for group in json.load(sys.stdin)["devices"].values():
    for device in group:
        if device["udid"] == device_id:
            print(device["state"])
            sys.exit(0)
sys.exit("Requested simulator is not available: " + device_id)
' "$device")
if [[ $state != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ -d "$developer_dir/Applications/Simulator.app" ]]; then
  open -a "$developer_dir/Applications/Simulator.app" --args -CurrentDeviceUDID "$device"
elif [[ -d "$developer_dir/../Applications/DeviceHub.app" ]]; then
  # Xcode 27 presents devices through Device Hub instead of the old Simulator app.
  open -a "$developer_dir/../Applications/DeviceHub.app"
else
  echo "Simulator GUI not found; the app will run in the booted simulator. Open the device in Xcode." >&2
fi
xcrun simctl install "$device" "$app_bundle"
args=(-demoLanguage "$language" -demoTab "$tab" -demoSeed "$seed" -debug.dayOffset 0)
if [[ -n $route ]]; then args+=(-demoRoute "$route"); fi
xcrun simctl launch --terminate-running-process "$device" "$bundle_id" "${args[@]}"
echo "Started $language demo on $device. Learning records and saved poems are retained."
