#!/usr/bin/env bash

set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
local_properties="$project_dir/android/local.properties"
backend_port="${BACKEND_PORT:-8000}"
package_name="com.coderpwh.agent_voice_app"

property_value() {
  local name="$1"
  sed -n "s/^${name}=//p" "$local_properties" | tail -1
}

flutter_bin="${FLUTTER_BIN:-}"
if [[ -z "$flutter_bin" ]]; then
  flutter_sdk=$(property_value flutter.sdk)
  flutter_bin="$flutter_sdk/bin/flutter"
fi

adb_bin="${ADB_BIN:-}"
if [[ -z "$adb_bin" ]]; then
  android_sdk=$(property_value sdk.dir)
  adb_bin="$android_sdk/platform-tools/adb"
fi

if [[ ! -x "$flutter_bin" ]]; then
  echo "Flutter executable not found: $flutter_bin" >&2
  exit 1
fi
if [[ ! -x "$adb_bin" ]]; then
  echo "ADB executable not found: $adb_bin" >&2
  exit 1
fi

device_id="${1:-}"
if [[ -z "$device_id" ]]; then
  devices=$(
    "$adb_bin" devices |
      awk 'NR > 1 && $2 == "device" { print $1 }'
  )
  device_count=$(printf '%s\n' "$devices" | awk 'NF { count++ } END { print count + 0 }')
  if [[ "$device_count" -ne 1 ]]; then
    echo "Expected one connected device, found $device_count. Pass its serial as the first argument." >&2
    exit 1
  fi
  device_id="$devices"
fi

base_url="http://127.0.0.1:$backend_port"
apk_path="$project_dir/build/app/outputs/flutter-apk/app-debug.apk"

cd "$project_dir"
"$flutter_bin" build apk --debug --dart-define="API_BASE_URL=$base_url"
"$adb_bin" -s "$device_id" install -r "$apk_path"
"$adb_bin" -s "$device_id" reverse "tcp:$backend_port" "tcp:$backend_port"
"$adb_bin" -s "$device_id" shell am force-stop "$package_name"
"$adb_bin" -s "$device_id" shell am start -n "$package_name/.MainActivity"

echo "Installed $apk_path on $device_id"
echo "Backend route: device $base_url -> host 127.0.0.1:$backend_port"
