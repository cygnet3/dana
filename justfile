default: run

# use fvm if available, else use flutter directly
flutter := if `which fvm 2> /dev/null || true` != "" { "fvm flutter" }  else { "flutter" }

# target platform that is automatically chosen when using 'flutter run'
platform := `fvm flutter devices --machine | jq .[0].targetPlatform`

git_hash := `git rev-parse HEAD`

run flags="":
    #!/bin/sh
    just gen

    flags={{flags}}
    flags="$flags --flavor local"
    flags="$flags --target lib/main_local.dart"
    flags="$flags --dart-define=GIT_HASH={{git_hash}}"

    {{flutter}} run $flags

run-release:
    just run --release

format:
    fvm dart format ./lib

gen:
    cd rust && just gen

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
