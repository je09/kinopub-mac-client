#!/usr/bin/env ruby
# add-source.rb — register a Swift file in KinoPubAppleClient.xcodeproj.
# Usage: ruby scripts/add-source.rb <relative/path/File.swift> [<PBXGroup path>] [app|tests]
# The group is found by walking the group tree with `path = ...`; default is the file's dirname
# (or the test group when target is `tests`).
require 'set'

project = 'KinoPubAppleClient.xcodeproj/project.pbxproj'
path = ARGV[0]
group_path = ARGV[1]
target = ARGV[2] || 'app'
abort 'usage: add-source.rb <File.swift> [group] [app|tests]' unless path

app_sources_phase = 'CC88E1DD2A6586E600E9387F'
tests_sources_phase = 'D00000000000000000000031'
tests_group = 'KinoPubAppleClientTests'
phase = target == 'tests' ? tests_sources_phase : app_sources_phase

text = File.read(project)
abort "already in project: #{path}" if text.include?("/* #{File.basename(path)} */")

# 24-hex-char IDs, unique vs the file.
used = text.scan(/[A-F0-9]{24}/).to_set
id = nil
counter = 1
loop do
  candidate = format('BBBBBBBB000000000000%04X', counter)
  unless used.include?(candidate)
    id = candidate
    break
  end
  counter += 1
end

name = File.basename(path)
ref = format('/* %s */', name)

# 1. PBXFileReference
ref_line = "\t\t#{id} #{ref} = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{name}; sourceTree = \"<group>\"; };"
text.sub!(/^(\t\t[A-F0-9]{24} \/\* .* \*\/ = \{isa = PBXFileReference;.*\n)/) { ref_line + "\n" + $1 }

# 2. PBXBuildFile (Sources)
build_id = id + 'X' # 24 hex chars; X is not hex — rebuild properly below
build_id = format('BBBBBBBB000000000001%04X', counter)
build_line = "\t\t#{build_id} /* #{name} in Sources */ = {isa = PBXBuildFile; fileRef = #{id} #{ref}; };"
text.sub!(/^(\t\t[A-F0-9]{24} \/\* .* in Sources \*\/ = \{isa = PBXBuildFile;.*\n)/) { build_line + "\n" + $1 }

# 3. Group children — find the group whose `path` matches (or dirname by default)
dir = group_path || (target == 'tests' ? tests_group : File.dirname(path))
dir = 'MediaItem' if dir == '.'
group_regex = /(\t\t[A-F0-9]{24} \/\* #{Regexp.escape(dir)} \*\/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)([\s\S]*?)(\n\t\t\t\);\n\t\t\tpath = #{Regexp.escape(dir)};)/
m = text.match(group_regex)
abort "group not found: #{dir}" unless m
insert = "\t\t\t\t#{id} #{ref},"
text.sub!(group_regex) { $1 + insert + "\n" + $2 + $3 }

# 4. Sources build phase (target's Sources phase)
sources_marker = /(#{phase} \/\* Sources \*\/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = \(\n)(.*?)(\n\t\t\t\);)/m
sm = text.match(sources_marker)
abort 'sources phase not found' unless sm
text.sub!(sources_marker) { $1 + "\t\t\t\t#{build_id} /* #{name} in Sources */,\n" + $2 + $3 }

File.write(project, text)
puts "added #{path} -> group #{dir} (ref #{id}, build #{build_id}, target #{target})"
