#!/usr/bin/env ruby

require 'xcodeproj'

project = Xcodeproj::Project.open('/Volumes/Data/xcode/RsyncGUI/RsyncGUI.xcodeproj')
target = project.targets.first
models_group = project['RsyncGUI']['Models']
services_group = project['RsyncGUI']['Services']

# Add new model files
['ParallelismConfig.swift', 'DeltaReport.swift'].each do |filename|
  path = "RsyncGUI/Models/#{filename}"
  if File.exist?(path)
    file_ref = models_group.new_file(path)
    target.add_file_references([file_ref])
    puts "Added: Models/#{filename}"
  end
end

# Add new service file
service_file = 'RsyncGUI/Services/AdvancedExecutionService.swift'
if File.exist?(service_file)
  file_ref = services_group.new_file(service_file)
  target.add_file_references([file_ref])
  puts "Added: Services/AdvancedExecutionService.swift"
end

project.save
puts "✅ Project updated with new files"
