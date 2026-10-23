#!/usr/bin/env python3
"""Build an unsigned Xcode project from the matching official Godot iOS template."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parents[1]
BINARY = "DungeonChasers"
TEMPLATE_NAME = "godot_apple_embedded"
TARGET_ID = "D0BCFE3318AEBDA2004A7AAE"
PLACEHOLDER = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*")
SOURCE_URL = (
    "https://github.com/godotengine/godot/blob/4.7-stable/"
    "editor/export/editor_export_platform_apple_embedded.cpp"
)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def render(text, replacements, label):
    missing = sorted(set(PLACEHOLDER.findall(text)) - replacements.keys())
    if missing:
        raise ValueError(f"Unknown {label} placeholders: {missing}")
    result = PLACEHOLDER.sub(lambda match: replacements[match.group()], text)
    if PLACEHOLDER.search(result):
        raise ValueError(f"Unrendered {label} placeholder")
    return result


def write_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as target:
        plistlib.dump(value, target, sort_keys=False)


def run(command, log_path, environment=None):
    print("Running:", " ".join(str(part) for part in command), flush=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w") as log:
        result = subprocess.run(
            [str(part) for part in command], cwd=ROOT, env=environment,
            stdout=log, stderr=subprocess.STDOUT, check=False,
        )
    return {"command": [str(part) for part in command], "exit_code": result.returncode,
            "log": str(log_path)}


def verify_unsigned_app(app, pck):
    executable = app / BINARY
    packed = app / pck.name
    if not executable.is_file() or not packed.is_file():
        raise ValueError("Native build did not produce executable and PCK")
    architecture = subprocess.run(["lipo", "-archs", executable], capture_output=True,
                                  text=True, check=False)
    if architecture.returncode or "arm64" not in architecture.stdout.split():
        raise ValueError("Unsigned executable is not arm64")
    if sha256(packed) != sha256(pck):
        raise ValueError("App PCK differs from exported PCK")
    signature = subprocess.run(["codesign", "-dv", app], capture_output=True,
                              text=True, check=False)
    return {"executable": str(executable), "architectures": architecture.stdout.strip(),
            "executable_bytes": executable.stat().st_size, "pack_sha256_matches": True,
            "signature_check_exit_code": signature.returncode,
            "signature_check_output": signature.stderr.strip(),
            "code_signature_present": (app / "_CodeSignature").exists()}


def pbx_replacements(bundle_id):
    values = {name: "" for name in (
        "additional_pbx_files additional_pbx_frameworks_build "
        "additional_pbx_frameworks_refs additional_pbx_resources_build "
        "additional_pbx_resources_refs pbx_embeded_frameworks "
        "pbx_locale_build_reference pbx_locale_file_reference "
        "pbx_launch_screen_build_reference pbx_launch_screen_file_reference "
        "pbx_launch_screen_copy_files pbx_launch_screen_build_phase "
        "modules_buildfile modules_fileref modules_buildphase modules_buildgrp "
        "code_sign_identity_debug code_sign_identity_release "
        "provisioning_profile_specifier_debug provisioning_profile_specifier_release "
        "provisioning_profile_uuid_debug provisioning_profile_uuid_release"
    ).split()}
    values.update({
        "binary": BINARY, "name": "Dungeon Chasers", "bundle_identifier": bundle_id,
        "code_sign_style_debug": "Automatic", "code_sign_style_release": "Automatic",
        "godot_archs": "arm64", "valid_archs": "arm64", "sdkroot": "iphoneos",
        "os_deployment_target": "IPHONEOS_DEPLOYMENT_TARGET = 16.0;",
        "short_version": "0.1.0", "version": "1", "targeted_device_family": "1,2",
        "team_id": '""', "linker_flags": "",
        "moltenvk_buildfile": (
            "9039D3BE24C093AC0020482C = {isa = PBXBuildFile; "
            "fileRef = 9039D3BD24C093AC0020482C; };"),
        "moltenvk_fileref": (
            "9039D3BD24C093AC0020482C = {isa = PBXFileReference; "
            "lastKnownFileType = wrapper.xcframework; name = MoltenVK; "
            'path = MoltenVK.xcframework; sourceTree = "<group>"; };'),
        "moltenvk_buildphase": "9039D3BE24C093AC0020482C,",
        "moltenvk_buildgrp": "9039D3BD24C093AC0020482C,",
    })
    return {"$" + name: value for name, value in values.items()}


def make_project(template, output, bundle_id, configuration):
    replacements = pbx_replacements(bundle_id)
    framework_prefix = f"libgodot.ios.{configuration.lower()}.xcframework"
    selected = 0
    with zipfile.ZipFile(template) as archive:
        for entry in archive.infolist():
            name = entry.filename
            if entry.is_dir() or name.endswith("/empty"):
                continue
            if name.startswith(framework_prefix + "/"):
                relative = BINARY + ".xcframework" + name[len(framework_prefix):]
            elif name.startswith("MoltenVK.xcframework/"):
                relative = name
            elif name.startswith(TEMPLATE_NAME + "/"):
                if name.endswith(("export_options.plist", "-Info.plist", ".entitlements",
                                  ".storyboard")) or "/Images.xcassets/" in name:
                    continue
                relative = name.replace(TEMPLATE_NAME, BINARY)
            elif name.startswith(TEMPLATE_NAME + ".xcodeproj/"):
                relative = name.replace(TEMPLATE_NAME, BINARY)
            else:
                continue
            if ".." in PurePosixPath(relative).parts or relative.startswith("/"):
                raise ValueError("Unsafe template path: " + relative)
            destination = output / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            data = archive.read(entry)
            if destination.name == "project.pbxproj":
                text = render(data.decode(), replacements, "PBX")
                text = text.replace("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", "")
                text = "\n".join(line for line in text.splitlines()
                                 if "D07CD44D1C5D589C00B7FB28" not in line
                                 and "D07CD44E1C5D589C00B7FB28" not in line) + "\n"
                data = text.encode()
            elif destination.name == "dummy.cpp":
                data = render(data.decode(), {"$cpp_code": (
                    "void godot_apple_embedded_plugins_initialize() {}\n"
                    "void godot_apple_embedded_plugins_deinitialize() {}\n"
                )}, "plugin bridge").encode()
            elif destination.suffix == ".xcscheme":
                tree = ET.fromstring(render(data.decode(), {
                    "$binary": BINARY, "$default_build_config": configuration,
                }, "scheme"))
                for reference in tree.iter("BuildableReference"):
                    reference.set("BlueprintIdentifier", TARGET_ID)
                    reference.set("BuildableName", BINARY + ".app")
                    reference.set("BlueprintName", BINARY)
                    reference.set("ReferencedContainer", "container:" + BINARY + ".xcodeproj")
                data = ET.tostring(tree, encoding="utf-8", xml_declaration=True)
            destination.write_bytes(data)
            selected += 1
    source = output / BINARY
    orientations = ["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
    write_plist(source / f"{BINARY}-Info.plist", {
        "CFBundleDevelopmentRegion": "en", "CFBundleDisplayName": "Dungeon Chasers",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)", "LSRequiresIPhoneOS": True,
        "UIRequiredDeviceCapabilities": ["arm64"], "UIRequiresFullScreen": True,
        "UIStatusBarHidden": True, "UIViewControllerBasedStatusBarAppearance": False,
        "UISupportedInterfaceOrientations": orientations,
        "UISupportedInterfaceOrientations~ipad": orientations,
        "UILaunchScreen": {},
        "LSSupportsOpeningDocumentsInPlace": False, "UIFileSharingEnabled": False,
    })
    write_plist(source / f"{BINARY}.entitlements", {})
    # These are the matching Godot exporter's defaults, pending distribution review.
    write_plist(output / "PrivacyInfo.xcprivacy", {
        "NSPrivacyAccessedAPITypes": [
            {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
             "NSPrivacyAccessedAPITypeReasons": ["DDA9.1", "C617.1"]},
            {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategorySystemBootTime",
             "NSPrivacyAccessedAPITypeReasons": ["35F9.1"]},
            {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace",
             "NSPrivacyAccessedAPITypeReasons": ["E174.1", "85F4.1"]},
        ], "NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [],
        "NSPrivacyCollectedDataTypes": [],
    })
    for path in output.rglob("*.plist"):
        if "DerivedData" not in path.parts:
            with path.open("rb") as handle:
                plistlib.load(handle)
    for extension in ("*.pbxproj", "*.xcscheme", "*.storyboard", "*.cpp", "*.entitlements"):
        for path in output.rglob(extension):
            if "DerivedData" not in path.parts and PLACEHOLDER.search(path.read_text()):
                raise ValueError("Unrendered template in " + str(path))
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--template", type=Path, default=ROOT / ".local/templates/ios.zip")
    parser.add_argument("--output", type=Path, default=ROOT / "builds/ios/unsigned")
    parser.add_argument("--configuration", choices=["Debug", "Release"], default="Debug")
    parser.add_argument("--bundle-id", default="com.teamelo.dungeonchasers.godot")
    parser.add_argument("--skip-pack", action="store_true")
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--ads-godot-source", type=Path, help="Enable TopOn using matching Godot engine source headers")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9.-]+", args.bundle_id):
        parser.error("Invalid bundle identifier")
    output = args.output.resolve()
    builds = ROOT / "builds"
    if not output.is_relative_to(builds):
        parser.error("Output must stay inside this project's builds directory")
    builds.mkdir(exist_ok=True)
    (builds / ".gdignore").touch(exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    report_path = reports / "ios-unsigned.json"
    report = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "project_generation": "pending", "native_compilation": "not_requested",
        "signing": "not_performed_no_team_or_certificate_supplied",
        "device_installation": "not_performed_requires_signing",
        "ios_runtime": "unverified", "app_store_validation": "not_performed",
        "app_icon": "not_configured_original_apk_icon_not_verified",
        "launch_screen": "native_ios14_plist_avoids_storyboard_runtime_dependency",
        "privacy_manifest": "matching_godot_defaults_distribution_review_pending",
        "official_exporter_reference": SOURCE_URL,
        "configuration": args.configuration, "bundle_identifier": args.bundle_id,
        "template": str(args.template), "template_sha256": sha256(args.template),
        "output": str(output), "project": str(output / f"{BINARY}.xcodeproj"),
        "steps": {},
    }
    code = 0
    try:
        pck = builds / "ios" / f"{BINARY}.pck"
        if not args.skip_pack:
            report["steps"]["pack"] = run([
                args.godot, "--headless", "--path", ROOT,
                "--log-file", reports / "ios-pack-godot.log",
                "--export-pack", "iOS", pck,
            ], reports / "ios-pack-console.log")
            if report["steps"]["pack"]["exit_code"]:
                raise RuntimeError("Godot PCK export failed")
        with pck.open("rb") as handle:
            if handle.read(4) != b"GDPC":
                raise ValueError("PCK magic mismatch")
        report["pack"] = {"path": str(pck), "bytes": pck.stat().st_size,
                          "sha256": sha256(pck)}
        report["template_files"] = make_project(
            args.template, output, args.bundle_id, args.configuration,
        )
        shutil.copy2(pck, output / pck.name)
        project = output / f"{BINARY}.xcodeproj"
        if args.ads_godot_source:
            report["steps"]["ads_project"] = run([
                "ruby", ROOT / "tools/configure_ios_ads.rb", output, args.ads_godot_source.resolve(),
            ], reports / "ios-ads-project.log")
            if report["steps"]["ads_project"]["exit_code"]:
                raise RuntimeError("Advertising project configuration failed")
            report["steps"]["ads_dependencies"] = run([
                "pod", "install", "--project-directory=" + str(output),
            ], reports / "ios-ads-pods.log")
            if report["steps"]["ads_dependencies"]["exit_code"]:
                raise RuntimeError("Advertising CocoaPods dependencies failed")
            report["advertising"] = "topon_admob_rewarded"
        report["steps"]["pbx_validation"] = run([
            "plutil", "-lint", project / "project.pbxproj",
        ], reports / "ios-project-validation.log")
        if report["steps"]["pbx_validation"]["exit_code"]:
            raise RuntimeError("Xcode project syntax validation failed")
        report["project_generation"] = "passed"
        version = subprocess.run(["xcodebuild", "-version"], capture_output=True,
                                 text=True, check=False)
        report["xcode"] = version.stdout.strip()
        if args.build:
            derived = output / "DerivedData"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(output / "ModuleCache")
            environment["SWIFT_MODULE_CACHE_PATH"] = str(output / "SwiftModuleCache")
            report["steps"]["native_build"] = run([
                "xcodebuild", "-workspace" if args.ads_godot_source else "-project",
                output / f"{BINARY}.xcworkspace" if args.ads_godot_source else project, "-scheme", BINARY,
                "-configuration", args.configuration, "-sdk", "iphoneos",
                "-destination", "generic/platform=iOS", "-derivedDataPath", derived,
                "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "DEVELOPMENT_TEAM=",
                "CLANG_MODULE_CACHE_PATH=" + str(output / "ModuleCache"),
                "SWIFT_MODULE_CACHE_PATH=" + str(output / "SwiftModuleCache"), "build",
            ], reports / "ios-unsigned-build.log", environment)
            native_code = report["steps"]["native_build"]["exit_code"]
            report["native_compilation"] = "passed" if native_code == 0 else "failed"
            app = derived / "Build/Products" / (args.configuration + "-iphoneos") / (BINARY + ".app")
            report["unsigned_app"] = str(app) if app.is_dir() else None
            if native_code == 0:
                report["artifact_validation"] = verify_unsigned_app(app, pck)
            code = 0 if native_code == 0 else 1
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
        report["error"] = str(error)
        code = 1
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"project_generation": report["project_generation"],
                      "native_compilation": report["native_compilation"],
                      "report": str(report_path), "error": report.get("error")}, indent=2))
    return code


if __name__ == "__main__":
    sys.exit(main())
