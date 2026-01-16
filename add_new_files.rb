#!/usr/bin/env ruby

require 'xcodeproj'

project = Xcodeproj::Project.open('/Volumes/Data/xcode/RsyncGUI/RsyncGUI.xcodeproj')
target = project.targets.first
models_group = project['RsyncGUI']['Models']
services_group = project['RsyncGUI']['Services']

# Create Design group if it doesn't exist
design_group = project['RsyncGUI']['Design'] || project['RsyncGUI'].new_group('Design')

# Add new model files
['ParallelismConfig.swift', 'DeltaReport.swift'].each do |filename|
  path = "RsyncGUI/Models/#{filename}"
  if File.exist?(path)
    file_ref = models_group.new_file(path)
    target.add_file_references([file_ref])
    puts "Added: Models/#{filename}"
  end
end

# Add new service files
['AdvancedExecutionService.swift', 'MenuBarManager.swift'].each do |filename|
  service_file = "RsyncGUI/Services/#{filename}"
  if File.exist?(service_file)
    file_ref = services_group.new_file(service_file)
    target.add_file_references([file_ref])
    puts "Added: Services/#{filename}"
  end
end

# Add design system file
design_file = 'RsyncGUI/Design/ModernDesign.swift'
if File.exist?(design_file)
  file_ref = design_group.new_file(design_file)
  target.add_file_references([file_ref])
  puts "Added: Design/ModernDesign.swift"
end

project.save
puts "✅ Project updated with new files"
