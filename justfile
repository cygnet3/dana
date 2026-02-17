default: run

# use fvm if available, else use flutter directly
flutter := if `which fvm 2> /dev/null || true` != "" { "fvm flutter" }  else { "flutter" }

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

gen-rust:
    just gen
    just build-android
