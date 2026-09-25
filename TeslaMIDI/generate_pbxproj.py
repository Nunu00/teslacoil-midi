import os
import hashlib

def det_id(name):
    # Generates a consistent 24-character hex string based on name
    return hashlib.sha1(name.encode('utf-8')).hexdigest()[:24].upper()

bundled_dir = "TeslaMIDI/TeslaMIDI/BundledMIDIs"
midi_files = sorted([f for f in os.listdir(bundled_dir) if f.endswith('.mid')])
print(f"Found {len(midi_files)} bundled MIDI files to embed into project.")

# Generate PBXBuildFile entries for MIDIs
midi_bf_lines = []
for f in midi_files:
    midi_bf_lines.append(f'\t\t{det_id("BF_MIDI_" + f)} /* {f} in Resources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_MIDI_" + f)} /* {f} */; }};')
midi_bf_str = "\n".join(midi_bf_lines)

# Generate PBXFileReference entries for MIDIs
midi_fr_lines = []
for f in midi_files:
    midi_fr_lines.append(f'\t\t{det_id("FR_MIDI_" + f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = audio.midi; path = "{f}"; sourceTree = "<group>"; }};')
midi_fr_str = "\n".join(midi_fr_lines)

# Generate Group children for BundledMIDIs
midi_grp_children = "\n".join([f'\t\t\t\t{det_id("FR_MIDI_" + f)} /* {f} */,' for f in midi_files])

# Generate Resources phase entries
midi_res_entries = "\n".join([f'\t\t\t\t{det_id("BF_MIDI_" + f)} /* {f} in Resources */,' for f in midi_files])

pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
		{det_id("BF_App") } /* TeslaMIDIApp.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_App")} /* TeslaMIDIApp.swift */; }};
		{det_id("BF_TrackInfo") } /* MIDITrackInfo.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_TrackInfo")} /* MIDITrackInfo.swift */; }};
		{det_id("BF_Parser") } /* MIDIParser.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_Parser")} /* MIDIParser.swift */; }};
		{det_id("BF_BTService") } /* BluetoothService.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_BTService")} /* BluetoothService.swift */; }};
		{det_id("BF_Engine") } /* MIDIPlaybackEngine.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_Engine")} /* MIDIPlaybackEngine.swift */; }};
		{det_id("BF_Storage") } /* SongStorageService.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_Storage")} /* SongStorageService.swift */; }};
		{det_id("BF_AudioSynth") } /* AudioToneSynthesizer.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_AudioSynth")} /* AudioToneSynthesizer.swift */; }};
		{det_id("BF_Content") } /* ContentView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_Content")} /* ContentView.swift */; }};
		{det_id("BF_SongList") } /* SongListView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_SongList")} /* SongListView.swift */; }};
		{det_id("BF_TrackSel") } /* TrackSelectorView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_TrackSel")} /* TrackSelectorView.swift */; }};
		{det_id("BF_BTModal") } /* BluetoothModalView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_BTModal")} /* BluetoothModalView.swift */; }};
		{det_id("BF_Settings") } /* SettingsView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_Settings")} /* SettingsView.swift */; }};
		{det_id("BF_Assets") } /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_Assets")} /* Assets.xcassets */; }};
		{det_id("BF_CB_FW") } /* CoreBluetooth.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_CB_FW")} /* CoreBluetooth.framework */; }};
		{det_id("BF_AV_FW") } /* AVFoundation.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {det_id("FR_AV_FW")} /* AVFoundation.framework */; }};
{midi_bf_str}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{det_id("FR_Product") } /* TeslaMIDI.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TeslaMIDI.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{det_id("FR_App") } /* TeslaMIDIApp.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TeslaMIDIApp.swift; sourceTree = "<group>"; }};
		{det_id("FR_TrackInfo") } /* MIDITrackInfo.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MIDITrackInfo.swift; sourceTree = "<group>"; }};
		{det_id("FR_Parser") } /* MIDIParser.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MIDIParser.swift; sourceTree = "<group>"; }};
		{det_id("FR_BTService") } /* BluetoothService.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BluetoothService.swift; sourceTree = "<group>"; }};
		{det_id("FR_Engine") } /* MIDIPlaybackEngine.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MIDIPlaybackEngine.swift; sourceTree = "<group>"; }};
		{det_id("FR_Storage") } /* SongStorageService.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SongStorageService.swift; sourceTree = "<group>"; }};
		{det_id("FR_AudioSynth") } /* AudioToneSynthesizer.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AudioToneSynthesizer.swift; sourceTree = "<group>"; }};
		{det_id("FR_Content") } /* ContentView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ContentView.swift; sourceTree = "<group>"; }};
		{det_id("FR_SongList") } /* SongListView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SongListView.swift; sourceTree = "<group>"; }};
		{det_id("FR_TrackSel") } /* TrackSelectorView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TrackSelectorView.swift; sourceTree = "<group>"; }};
		{det_id("FR_BTModal") } /* BluetoothModalView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BluetoothModalView.swift; sourceTree = "<group>"; }};
		{det_id("FR_Settings") } /* SettingsView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; }};
		{det_id("FR_InfoPlist") } /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{det_id("FR_Assets") } /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
		{det_id("FR_CB_FW") } /* CoreBluetooth.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = CoreBluetooth.framework; path = System/Library/Frameworks/CoreBluetooth.framework; sourceTree = SDKROOT; }};
		{det_id("FR_AV_FW") } /* AVFoundation.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = AVFoundation.framework; path = System/Library/Frameworks/AVFoundation.framework; sourceTree = SDKROOT; }};
{midi_fr_str}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{det_id("BP_Frameworks") } /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{det_id("BF_CB_FW") } /* CoreBluetooth.framework in Frameworks */,
				{det_id("BF_AV_FW") } /* AVFoundation.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{det_id("GRP_Main") } = {{
			isa = PBXGroup;
			children = (
				{det_id("GRP_App") } /* TeslaMIDI */,
				{det_id("GRP_Frameworks") } /* Frameworks */,
				{det_id("GRP_Products") } /* Products */,
			);
			sourceTree = "<group>";
		}};
		{det_id("GRP_App") } /* TeslaMIDI */ = {{
			isa = PBXGroup;
			children = (
				{det_id("FR_App") } /* TeslaMIDIApp.swift */,
				{det_id("GRP_Models") } /* Models */,
				{det_id("GRP_Services") } /* Services */,
				{det_id("GRP_Views") } /* Views */,
				{det_id("GRP_BundledMIDIs") } /* BundledMIDIs */,
				{det_id("FR_Assets") } /* Assets.xcassets */,
				{det_id("FR_InfoPlist") } /* Info.plist */,
			);
			path = TeslaMIDI;
			sourceTree = "<group>";
		}};
		{det_id("GRP_Models") } /* Models */ = {{
			isa = PBXGroup;
			children = (
				{det_id("FR_TrackInfo") } /* MIDITrackInfo.swift */,
				{det_id("FR_Parser") } /* MIDIParser.swift */,
			);
			path = Models;
			sourceTree = "<group>";
		}};
		{det_id("GRP_Services") } /* Services */ = {{
			isa = PBXGroup;
			children = (
				{det_id("FR_BTService") } /* BluetoothService.swift */,
				{det_id("FR_Engine") } /* MIDIPlaybackEngine.swift */,
				{det_id("FR_Storage") } /* SongStorageService.swift */,
				{det_id("FR_AudioSynth") } /* AudioToneSynthesizer.swift */,
			);
			path = Services;
			sourceTree = "<group>";
		}};
		{det_id("GRP_Views") } /* Views */ = {{
			isa = PBXGroup;
			children = (
				{det_id("FR_Content") } /* ContentView.swift */,
				{det_id("FR_SongList") } /* SongListView.swift */,
				{det_id("FR_TrackSel") } /* TrackSelectorView.swift */,
				{det_id("FR_BTModal") } /* BluetoothModalView.swift */,
				{det_id("FR_Settings") } /* SettingsView.swift */,
			);
			path = Views;
			sourceTree = "<group>";
		}};
		{det_id("GRP_BundledMIDIs") } /* BundledMIDIs */ = {{
			isa = PBXGroup;
			children = (
{midi_grp_children}
			);
			path = BundledMIDIs;
			sourceTree = "<group>";
		}};
		{det_id("GRP_Frameworks") } /* Frameworks */ = {{
			isa = PBXGroup;
			children = (
				{det_id("FR_CB_FW") } /* CoreBluetooth.framework */,
				{det_id("FR_AV_FW") } /* AVFoundation.framework */,
			);
			name = Frameworks;
			sourceTree = "<group>";
		}};
		{det_id("GRP_Products") } /* Products */ = {{
			isa = PBXGroup;
			children = (
				{det_id("FR_Product") } /* TeslaMIDI.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{det_id("TARGET_App") } /* TeslaMIDI */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {det_id("CFG_TargetList") } /* Build configuration list for PBXNativeTarget "TeslaMIDI" */;
			buildPhases = (
				{det_id("BP_Sources") } /* Sources */,
				{det_id("BP_Frameworks") } /* Frameworks */,
				{det_id("BP_Resources") } /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = TeslaMIDI;
			productName = TeslaMIDI;
			productReference = {det_id("FR_Product") } /* TeslaMIDI.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{det_id("PROJ_Root") } /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastUpgradeCheck = 1500;
				TargetAttributes = {{
					{det_id("TARGET_App") } = {{
						CreatedOnToolsVersion = 15.0;
					}};
				}};
			}};
			buildConfigurationList = {det_id("CFG_ProjectList") } /* Build configuration list for PBXProject "TeslaMIDI" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = it;
			hasScannedForEncodings = 0;
			knownRegions = (
				it,
				Base,
			);
			mainGroup = {det_id("GRP_Main") };
			productRefGroup = {det_id("GRP_Products") } /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{det_id("TARGET_App") } /* TeslaMIDI */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{det_id("BP_Resources") } /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{det_id("BF_Assets") } /* Assets.xcassets in Resources */,
{midi_res_entries}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{det_id("BP_Sources") } /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{det_id("BF_App") } /* TeslaMIDIApp.swift in Sources */,
				{det_id("BF_TrackInfo") } /* MIDITrackInfo.swift in Sources */,
				{det_id("BF_Parser") } /* MIDIParser.swift in Sources */,
				{det_id("BF_BTService") } /* BluetoothService.swift in Sources */,
				{det_id("BF_Engine") } /* MIDIPlaybackEngine.swift in Sources */,
				{det_id("BF_Storage") } /* SongStorageService.swift in Sources */,
				{det_id("BF_AudioSynth") } /* AudioToneSynthesizer.swift in Sources */,
				{det_id("BF_Content") } /* ContentView.swift in Sources */,
				{det_id("BF_SongList") } /* SongListView.swift in Sources */,
				{det_id("BF_TrackSel") } /* TrackSelectorView.swift in Sources */,
				{det_id("BF_BTModal") } /* BluetoothModalView.swift in Sources */,
				{det_id("BF_Settings") } /* SettingsView.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{det_id("CFG_Proj_Debug") } /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = NO;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDEFINED_VARIABLES = YES;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{det_id("CFG_Proj_Release") } /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = NO;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDEFINED_VARIABLES = YES;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{det_id("CFG_Target_Debug") } /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_IDENTITY = "";
				CODE_SIGN_STYLE = Manual;
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = TeslaMIDI/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.teslacoil.teslamidi;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{det_id("CFG_Target_Release") } /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_IDENTITY = "";
				CODE_SIGN_STYLE = Manual;
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = TeslaMIDI/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.teslacoil.teslamidi;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{det_id("CFG_ProjectList") } /* Build configuration list for PBXProject "TeslaMIDI" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{det_id("CFG_Proj_Debug") } /* Debug */,
				{det_id("CFG_Proj_Release") } /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{det_id("CFG_TargetList") } /* Build configuration list for PBXNativeTarget "TeslaMIDI" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{det_id("CFG_Target_Debug") } /* Debug */,
				{det_id("CFG_Target_Release") } /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

	}};
	rootObject = {det_id("PROJ_Root") } /* Project object */;
}}
"""

with open("TeslaMIDI/TeslaMIDI.xcodeproj/project.pbxproj", "w", encoding="utf-8") as f:
    f.write(pbx)
print("Updated project.pbxproj with all bundled MIDIs successfully!")
