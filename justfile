default: run

# use fvm if available, else use flutter directly
flutter := if `which fvm 2> /dev/null || true` != "" { "fvm flutter" }  else { "flutter" }

# target platform that is automatically chosen when using 'flutter run'
platform := `fvm flutter devices --machine | jq .[0].targetPlatform`

run:
    just gen
    {{flutter}} run --flavor local --target lib/main_local.dart --dart-define="GIT_HASH=$(git rev-parse HEAD)"
run-release:
    just gen
    {{flutter}} run --release --flavor local --target lib/main_local.dart --dart-define="GIT_HASH=$(git rev-parse HEAD)"

clean-bin:
    cd rust && just clean-bin
gen:
    cd rust && just gen
build-emulator:
    cd rust && just build-emulator
build-android:
    cd rust && just build-android

inspect-db:
    #!/bin/sh
    case {{platform}} in
        "android-arm64")
          adb exec-out run-as dev.silentpayments.danawallet.local dd if=/data/user/0/dev.silentpayments.danawallet.local/databases/dana.db > /tmp/dana.db
          sqlite3 /tmp/dana.db
        ;;
        "linux-x64")
          sqlite3 .dart_tool/sqflite_common_ffi/databases/dana.db
        ;;
        *) echo "unknown platform: {{platform}}"
    esac
