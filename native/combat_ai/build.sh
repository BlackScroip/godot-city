#!/bin/sh
set -eu

platform=android
configuration=all
godot_bin=${CITY_GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
ndk_path=${ANDROID_NDK_HOME:-/Users/7700k/Library/Android/sdk/ndk/28.2.13676358}
work_path=${CITY_NATIVE_BUILD_ROOT:-/private/tmp/city-native-ai}
jobs=${CITY_NATIVE_BUILD_JOBS:-6}
dependency_commit=8070599885b6df675fcad033dd032ce44be2b850

while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform) platform=$2; shift 2 ;;
    --configuration) configuration=$2; shift 2 ;;
    --godot) godot_bin=$2; shift 2 ;;
    --ndk) ndk_path=$2; shift 2 ;;
    --work) work_path=$2; shift 2 ;;
    --jobs) jobs=$2; shift 2 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
case "$platform" in android|macos) ;; *) exit 2 ;; esac
case "$configuration" in all|debug|release) ;; *) exit 2 ;; esac

script_path=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_path=$(CDPATH= cd -- "$script_path/../.." && pwd)
runtime_path=$project_path/goDot/addons/combat_ai/runtime
dependency_path=${CITY_GODOT_CPP_SOURCE:-$work_path/godot-cpp}
api_path=$work_path/api
mkdir -p "$api_path" "$runtime_path" "$work_path"
engine_version=$("$godot_bin" --version)
case "$engine_version" in
  4.7.2.stable.official.ed1daf0bf*) ;;
  *) printf 'Expected Godot 4.7.2 ed1daf0bf, got %s\n' "$engine_version" >&2; exit 1 ;;
esac
if [ ! -d "$dependency_path/.git" ]; then
  git clone https://github.com/godotengine/godot-cpp.git "$dependency_path"
  git -C "$dependency_path" checkout --detach "$dependency_commit"
fi
if [ "$(git -C "$dependency_path" rev-parse HEAD)" != "$dependency_commit" ]; then
  printf 'Unexpected godot-cpp revision in %s\n' "$dependency_path" >&2
  exit 1
fi
cp "$dependency_path/LICENSE.md" "$runtime_path/../LICENSE.godot-cpp.txt"
(
  cd "$api_path"
  "$godot_bin" --headless --log-file "$work_path/api.log" --dump-extension-api
)
if [ "$configuration" = all ]; then configurations='debug release'; else configurations=$configuration; fi
for build_configuration in $configurations; do
  build_path=$work_path/$platform-$build_configuration
  set -- -S "$script_path" -B "$build_path" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DGODOT_CPP_SOURCE="$dependency_path" \
    -DCITY_EXTENSION_API="$api_path/extension_api.json" \
    -DCITY_TARGET=template_$build_configuration
  if [ "$platform" = android ]; then
    set -- "$@" -DCMAKE_TOOLCHAIN_FILE="$ndk_path/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 -DANDROID_STL=c++_static
    library_name=libcombat_ai.so
    output_name=libcombat_ai.android.$build_configuration.arm64.so
  else
    set -- "$@" -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
    library_name=libcombat_ai.dylib
    output_name=libcombat_ai.macos.$build_configuration.arm64.dylib
  fi
  cmake "$@"
  cmake --build "$build_path" --target combat_ai --parallel "$jobs"
  cp "$build_path/$library_name" "$runtime_path/$output_name"
done
