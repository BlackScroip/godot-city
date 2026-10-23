require 'xcodeproj'
require 'fileutils'
require 'json'

output, headers = ARGV
abort 'Usage: configure_ios_ads.rb EXPORTED_PROJECT GODOT_SOURCE' unless output && headers
root = File.expand_path('..', __dir__)
abort 'Matching Godot source headers are required' unless File.file?(File.join(headers, 'core/config/engine.h'))
project = Xcodeproj::Project.open(File.join(output, 'DungeonChasers.xcodeproj'))
target = project.targets.find { |item| item.name == 'DungeonChasers' }
abort 'DungeonChasers target missing' unless target
source = File.join(root, 'native/ios/DungeonAds.mm')
reference = project.files.find { |item| item.real_path.to_s == source } || project.main_group.new_file(source)
target.source_build_phase.add_file_reference(reference, true)
target.build_configurations.each do |config|
  config.build_settings['HEADER_SEARCH_PATHS'] = ['$(inherited)', headers, File.join(headers, 'platform/ios'), File.join(root, 'native/ios/include')]
  config.build_settings['CLANG_ENABLE_OBJC_ARC'] = 'YES'
  definitions = ['$(inherited)', 'IOS_ENABLED', 'UNIX_ENABLED']
  definitions += ['DEBUG_ENABLED', 'DEBUG_METHODS_ENABLED'] if config.name == 'Debug'
  config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = definitions
  config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++17'
  config.build_settings['OTHER_LDFLAGS'] = ['$(inherited)', '-ObjC']
end
project.save
dummy = File.join(output, 'DungeonChasers/dummy.cpp')
text = File.read(dummy)
text = text.sub('void godot_apple_embedded_plugins_initialize() {}', "void dungeon_ads_initialize();\nvoid godot_apple_embedded_plugins_initialize() { dungeon_ads_initialize(); }")
text = text.sub('void godot_apple_embedded_plugins_deinitialize() {}', "void dungeon_ads_deinitialize();\nvoid godot_apple_embedded_plugins_deinitialize() { dungeon_ads_deinitialize(); }")
File.write(dummy, text)
plist_path = File.join(output, 'DungeonChasers/DungeonChasers-Info.plist')
plist = Xcodeproj::Plist.read_from_path(plist_path)
ads = JSON.parse(File.read(File.join(root, 'assets/ads.json')))
plist['GADApplicationIdentifier'] = ads.fetch('ios').fetch('admob_app_id')
plist['GADDelayAppMeasurementInit'] = true
Xcodeproj::Plist.write_to_path(plist, plist_path)
FileUtils.cp(File.join(root, 'native/ios/Podfile'), File.join(output, 'Podfile'))
