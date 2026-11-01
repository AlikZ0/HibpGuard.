#!/usr/bin/env python3
"""Generate the dependency-free Xcode project from the supplied source tree."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
objects: dict[str, dict] = {}


def identifier(name: str) -> str:
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


class Ref(str):
    pass


def ref(name: str) -> Ref:
    return Ref(identifier(name))


def add(object_key: str, isa: str, **values) -> Ref:
    key = ref(object_key)
    if key in objects:
        raise ValueError(f"Duplicate object: {object_key}")
    objects[key] = {"isa": isa, **values}
    return key


def source_group(folder: Path, parent_key: str) -> tuple[Ref, list[Ref]]:
    children = []
    sources = []
    for path in sorted(folder.iterdir()):
        key = f"{parent_key}/{path.name}"
        if path.is_dir():
            group, nested = source_group(path, key)
            children.append(group)
            sources.extend(nested)
        elif path.suffix == ".swift":
            file_ref = add(key, "PBXFileReference", lastKnownFileType="sourcecode.swift",
                           path=path.name, sourceTree="<group>")
            build_ref = add(key + ":build", "PBXBuildFile", fileRef=file_ref)
            children.append(file_ref)
            sources.append(build_ref)
    group = add(parent_key, "PBXGroup", children=children, path=folder.name, sourceTree="<group>")
    return group, sources


def configurations(key: str, settings: dict, debug: dict | None = None, release: dict | None = None) -> Ref:
    entries = []
    for name, extra in [("Debug", debug or {}), ("Release", release or {})]:
        entries.append(add(f"{key}:{name}", "XCBuildConfiguration", name=name,
                           buildSettings={**settings, **extra}))
    return add(key + ":config-list", "XCConfigurationList", buildConfigurations=entries,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")


app_group, app_sources = source_group(ROOT / "HibpGuard", "group:app")
test_group, test_sources = source_group(ROOT / "HibpGuardTests", "group:tests")
app_product = add("product:app", "PBXFileReference", explicitFileType="wrapper.application",
                  includeInIndex="0", path="HibpGuard.app", sourceTree="BUILT_PRODUCTS_DIR")
test_product = add("product:tests", "PBXFileReference", explicitFileType="wrapper.cfbundle",
                   includeInIndex="0", path="HibpGuardTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
products_group = add("group:products", "PBXGroup", children=[app_product, test_product],
                     name="Products", sourceTree="<group>")
main_group = add("group:main", "PBXGroup", children=[app_group, test_group, products_group], sourceTree="<group>")

project_config = configurations("project", {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES", "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE", "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "complete",
}, debug={
    "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"], "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
}, release={
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O", "VALIDATE_PRODUCT": "YES",
})

app_config = configurations("target:app", {
    "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_CFBundleDisplayName": "HibpGuard",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.utilities",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone":
        "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":
        "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0.0", "PRODUCT_BUNDLE_IDENTIFIER": "com.example.HibpGuard",
    "PRODUCT_NAME": "$(TARGET_NAME)", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO", "SWIFT_EMIT_LOC_STRINGS": "YES", "TARGETED_DEVICE_FAMILY": "1,2",
    "ENABLE_PREVIEWS": "YES",
})
test_config = configurations("target:tests", {
    "BUNDLE_LOADER": "$(TEST_HOST)", "CODE_SIGN_STYLE": "Automatic",
    "GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": "com.example.HibpGuardTests",
    "PRODUCT_NAME": "$(TARGET_NAME)", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "TARGETED_DEVICE_FAMILY": "1,2", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/HibpGuard.app/HibpGuard",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
})

app_phases = [add("phase:app:sources", "PBXSourcesBuildPhase", buildActionMask="2147483647",
                  files=app_sources, runOnlyForDeploymentPostprocessing="0"),
              add("phase:app:frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647",
                  files=[], runOnlyForDeploymentPostprocessing="0"),
              add("phase:app:resources", "PBXResourcesBuildPhase", buildActionMask="2147483647",
                  files=[], runOnlyForDeploymentPostprocessing="0")]
test_phases = [add("phase:tests:sources", "PBXSourcesBuildPhase", buildActionMask="2147483647",
                   files=test_sources, runOnlyForDeploymentPostprocessing="0"),
               add("phase:tests:frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647",
                   files=[], runOnlyForDeploymentPostprocessing="0"),
               add("phase:tests:resources", "PBXResourcesBuildPhase", buildActionMask="2147483647",
                   files=[], runOnlyForDeploymentPostprocessing="0")]
proxy = add("proxy:app", "PBXContainerItemProxy", containerPortal=ref("project"), proxyType="1",
             remoteGlobalIDString=ref("target:app"), remoteInfo="HibpGuard")
dependency = add("dependency:app", "PBXTargetDependency", target=ref("target:app"), targetProxy=proxy)
app_target = add("target:app", "PBXNativeTarget", buildConfigurationList=app_config,
                  buildPhases=app_phases, buildRules=[], dependencies=[], name="HibpGuard",
                  productName="HibpGuard", productReference=app_product,
                  productType="com.apple.product-type.application")
test_target = add("target:tests", "PBXNativeTarget", buildConfigurationList=test_config,
                   buildPhases=test_phases, buildRules=[], dependencies=[dependency], name="HibpGuardTests",
                   productName="HibpGuardTests", productReference=test_product,
                   productType="com.apple.product-type.bundle.unit-test")
project = add("project", "PBXProject", attributes={
    "BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600",
    "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "16.0"},
                         test_target: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app_target}},
}, buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="ru",
              hasScannedForEncodings="0", knownRegions=["ru", "en", "Base"], mainGroup=main_group,
              productRefGroup=products_group, projectDirPath="", projectRoot="", targets=[app_target, test_target])


def encode(value, indent=0):
    tab = "\t" * indent
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (indent + 1) + encode(k) + " = " + encode(v, indent + 1) + ";\n"
                                   for k, v in value.items()) + tab + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (indent + 1) + encode(v, indent + 1) + ",\n" for v in value) + tab + ")"
    if isinstance(value, Ref) or re.fullmatch(r"[A-Za-z0-9_./]+", str(value)):
        return str(value)
    return json.dumps(str(value), ensure_ascii=False)


project_dir = ROOT / "HibpGuard.xcodeproj"
project_dir.mkdir(exist_ok=True)
document = {"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project}
(project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode(document) + "\n")

scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")


def buildable(parent, target, filename, name):
    ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target,
                  BuildableName=filename, BlueprintName=name, ReferencedContainer="container:HibpGuard.xcodeproj")


build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
entries = ET.SubElement(build, "BuildActionEntries")
for target, filename, name, launch in [(app_target, "HibpGuard.app", "HibpGuard", "YES"),
                                      (test_target, "HibpGuardTests.xctest", "HibpGuardTests", "NO")]:
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning=launch,
                          buildForProfiling=launch, buildForArchiving=launch, buildForAnalyzing="YES")
    buildable(entry, target, filename, name)
test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                      selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
testable = ET.SubElement(ET.SubElement(test, "Testables"), "TestableReference", skipped="NO")
buildable(testable, test_target, "HibpGuardTests.xctest", "HibpGuardTests")
launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                        selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO",
                        ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal",
                        allowLocationSimulation="YES")
buildable(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), app_target, "HibpGuard.app", "HibpGuard")
profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES",
                         savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
buildable(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), app_target, "HibpGuard.app", "HibpGuard")
ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
ET.indent(scheme)
scheme_path = project_dir / "xcshareddata/xcschemes/HibpGuard.xcscheme"
scheme_path.parent.mkdir(parents=True, exist_ok=True)
ET.ElementTree(scheme).write(scheme_path, encoding="UTF-8", xml_declaration=True)
print(f"Generated {len(app_sources)} app sources and {len(test_sources)} test sources")
