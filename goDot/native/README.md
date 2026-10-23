# Advertising integration

The game uses TopOn rewarded video with AdMob Partner Bidding. Platform IDs are
in `assets/ads.json`; native AdMob application metadata must match that file.
Only the SDK reward event grants a reward. Close, failure, cancellation and
completion events do not grant anything. Android and iOS request UMP consent
before initialization and check `canRequestAds` before loading and showing.

## Android

Install the pinned Godot Android Gradle template under `android/build` first.
Build `native/android` with Java 17, Android SDK 36 and Gradle 8.14:

```sh
gradle -p native/android assembleDebug assembleRelease
```

For an existing matching engine library, pass `-PgodotLibrary=/absolute/path/to/godot-lib.aar`
or a classes JAR. This is compile-only; the runtime engine comes from the export
template. Copy both generated `DungeonAds-*.aar` files from
`native/android/build/outputs/aar` to `addons/dungeon_ads/bin`.

Then run `tools/build.py Android`.
The export plugin supplies SDK dependencies, repositories and the AAR. The AAR
manifest registers `DungeonAds` and supplies the Android AdMob application ID.
Do not reuse a template containing another application's native source or IDs.
This machine's generated template uses the Maven Central Google storage mirror
and Oracle JDK 17 because the default GraalVM failed Android SDK 36's JDK image
transform. Its local `settings.gradle` accepts `DUNGEON_ADS_OFFLINE=1` after
dependencies have been cached. These local build settings live under the
ignored `android/build` directory and must be reapplied if that directory is
recreated on this machine.

## iOS

Use the complete Godot 4.7.2 source tree matching the pinned engine, CocoaPods,
and Xcode with an installed iPhoneOS SDK:

```sh
python3 tools/export_ios_unsigned.py --ads-godot-source /absolute/path/to/godot-4.7.2 --build
```

The script installs pinned pods, adds `DungeonAds.mm`, registers the singleton,
sets AdMob metadata and builds the workspace. The generated GDExtension interface
header under `native/ios/include` was dumped by the project's pinned Godot engine.
The report is `reports/ios-unsigned.json`. Output is unsigned and requires a
development team and provisioning before device installation.

## Verification

Run `tests/ads_test.gd`, `tests/ads_ui_test.gd`, `tests/runtime_test.gd` and
`tests/systems_test.gd` with the pinned Godot executable. The first two cover
reward lifecycle, timeout retry, request deduplication, modal cancellation,
daily limits, free skips, meals and work acceleration.

Real device playback remains separate. Register test devices before ad testing;
do not click production ads. UMP message publication, iOS distribution privacy
declarations and signing still require the app's actual release information.
No interstitial, banner or app-open placements are configured. The reference
APK's extra-commission gameplay does not yet exist in this Godot project.
