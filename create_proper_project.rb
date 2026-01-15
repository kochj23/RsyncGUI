#!/usr/bin/env ruby

require 'xcodeproj'

project = Xcodeproj::Project.new('/Volumes/Data/xcode/RsyncGUI/RsyncGUI.xcodeproj')

# Create main target
target = project.new_target(:application, 'RsyncGUI', :osx)
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'RsyncGUI'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.jordankoch.rsyncgui'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['INFOPLIST_FILE'] = 'RsyncGUI/Info.plist'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['CODE_SIGN_IDENTITY'] = '-'
  config.build_settings['DEVELOPMENT_TEAM'] = ''
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
end

# Create main group structure
main_group = project.main_group['RsyncGUI'] || project.main_group.new_group('RsyncGUI')

# Add groups
models_group = main_group.new_group('Models')
views_group = main_group.new_group('Views')
services_group = main_group.new_group('Services')
resources_group = main_group.new_group('Resources')

# Add all Swift files
Dir.glob('RsyncGUI/**/*.swift').each do |file|
  relative_path = file.sub('RsyncGUI/', '')

  if file.include?('/Models/')
    file_ref = models_group.new_file(file)
  elsif file.include?('/Views/')
    file_ref = views_group.new_file(file)
  elsif file.include?('/Services/')
    file_ref = services_group.new_file(file)
  else
    file_ref = main_group.new_file(file)
  end

  target.add_file_references([file_ref])
  puts "Added: #{relative_path}"
end

# Add Info.plist
info_plist_ref = main_group.new_file('RsyncGUI/Info.plist')

# Add Assets.xcassets
assets_ref = resources_group.new_file('RsyncGUI/Resources/Assets.xcassets')
target.resources_build_phase.add_file_reference(assets_ref)

# Save project
project.save

puts "✅ Created proper Xcode project with all source files"
