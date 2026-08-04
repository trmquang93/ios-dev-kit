#!/usr/bin/env ruby
# Helper script for Xcode project file operations
# Usage: ruby xcodeproj_helper.rb [add|remove|list] [file-path] [options]
#
# Run from the directory that contains the .xcodeproj (project root).

require 'xcodeproj'
require 'optparse'
require 'pathname'

def find_project(explicit = nil)
  return explicit if explicit

  projects = Dir.glob('*.xcodeproj')
  if projects.empty?
    warn 'Error: No .xcodeproj file found in current directory'
    exit 1
  elsif projects.size > 1
    warn "Multiple projects found: #{projects.join(', ')}"
    warn 'Please specify project with --project option'
    exit 1
  end
  projects.first
end

def project_root(project_path)
  File.expand_path(File.dirname(project_path))
end

def normalize_relative_path(path)
  Pathname.new(path).cleanpath.to_s.delete_prefix('./')
end

def walk_groups(group, &block)
  return unless group.is_a?(Xcodeproj::Project::Object::PBXGroup)

  block.call(group)
  group.children.each do |child|
    walk_groups(child, &block) if child.is_a?(Xcodeproj::Project::Object::PBXGroup)
  end
end

# Find an existing PBXGroup whose on-disk folder matches `relative_dir`.
def find_group_for_directory(project, relative_dir)
  abs_dir = File.expand_path(relative_dir)
  found = nil

  walk_groups(project.main_group) do |group|
    next unless group.real_path

    if File.expand_path(group.real_path.to_s) == abs_dir
      found = group
      break
    end
  end

  found
end

# Walk or create groups for each path component under main_group.
def find_or_create_group_for_directory(project, relative_dir)
  existing = find_group_for_directory(project, relative_dir)
  return existing if existing

  group = project.main_group
  relative_dir.split('/').reject(&:empty?).each do |part|
    child = group[part] || group.children.find do |candidate|
      candidate.is_a?(Xcodeproj::Project::Object::PBXGroup) &&
        (candidate.name == part || candidate.path == part || candidate.display_name == part)
    end
    group = child || group.new_group(part, part)
  end

  group
end

def target_for(project, target_name)
  if target_name
    target = project.targets.find { |t| t.name == target_name }
    unless target
      warn "Warning: Target '#{target_name}' not found"
      warn 'Available targets:'
      project.targets.each { |t| warn "  - #{t.name}" }
    end
    return target
  end

  project.targets.first
end

def file_ref_in_target?(target, file_ref)
  target.source_build_phase.files.any? { |build_file| build_file.file_ref == file_ref }
end

def verify_file_ref(file_ref, expected_abs_path)
  resolved = File.expand_path(file_ref.real_path.to_s)
  return if resolved == expected_abs_path

  warn 'ERROR: File reference resolves to the wrong path on disk.'
  warn "  Expected: #{expected_abs_path}"
  warn "  Resolved: #{resolved}"
  warn "  PBX path: #{file_ref.path}"
  exit 1
end

def add_file(project_path, file_path, target_name)
  file_path = normalize_relative_path(file_path)
  filename = File.basename(file_path)
  relative_dir = File.dirname(file_path)

  root = project_root(project_path)
  expected_abs_path = File.expand_path(file_path, root)

  unless File.exist?(expected_abs_path)
    warn "Warning: File not on disk: #{expected_abs_path}"
  end

  project = Xcodeproj::Project.open(project_path)
  group = find_group_for_directory(project, relative_dir) ||
          find_or_create_group_for_directory(project, relative_dir)

  file_ref = group.files.find { |f| f.path == filename || f.display_name == filename }
  if file_ref
    puts "Already in project: #{file_path}"
  else
    # IMPORTANT: pass only the basename. The parent group's path provides the directory prefix.
    file_ref = group.new_file(filename)
    puts "Added: #{file_path}"
  end

  target = target_for(project, target_name)
  if target
    unless file_ref_in_target?(target, file_ref)
      target.add_file_references([file_ref])
    end
    puts "  Target: #{target.name}"
  else
    warn '  Target: none'
  end

  project.save
  verify_file_ref(file_ref, expected_abs_path)
  puts "  Group: #{group.hierarchy_path}"
  puts "  PBX path: #{file_ref.path}"
end

def remove_file(project_path, file_path)
  file_path = normalize_relative_path(file_path)
  root = project_root(project_path)
  expected_abs_path = File.expand_path(file_path, root)

  project = Xcodeproj::Project.open(project_path)

  file_ref = project.main_group.recursive_children.find do |child|
    next false unless child.is_a?(Xcodeproj::Project::Object::PBXFileReference)

    File.expand_path(child.real_path.to_s) == expected_abs_path ||
      child.path == file_path ||
      child.path == File.basename(file_path)
  end

  unless file_ref
    warn "Warning: File not found in project: #{file_path}"
    return
  end

  project.targets.each do |target|
    target.source_build_phase.remove_file_reference(file_ref)
  end

  file_ref.remove_from_project
  project.save
  puts "Removed: #{file_path}"
end

def list_targets(project_path)
  project = Xcodeproj::Project.open(project_path)
  puts "Targets in #{project_path}:"
  project.targets.each { |t| puts "  - #{t.name}" }
end

options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: xcodeproj_helper.rb [add|remove|list] [file-path] [options]'
  opts.on('-p', '--project PROJECT', 'Specify Xcode project file') { |p| options[:project] = p }
  opts.on('-t', '--target TARGET', 'Specify target name') { |t| options[:target] = t }
  opts.on('-h', '--help', 'Show this help') { puts opts; exit }
end.parse!

command = ARGV[0]
file_path = ARGV[1]
project_path = find_project(options[:project])

case command
when 'add'
  unless file_path
    warn 'Error: File path required for add command'
    exit 1
  end
  add_file(project_path, file_path, options[:target])
when 'remove'
  unless file_path
    warn 'Error: File path required for remove command'
    exit 1
  end
  remove_file(project_path, file_path)
when 'list'
  list_targets(project_path)
else
  warn "Error: Unknown command '#{command}'"
  warn 'Usage: xcodeproj_helper.rb [add|remove|list] [options]'
  exit 1
end
