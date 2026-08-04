---
name: xcode-project
description: Add/remove file references from Xcode project.pbxproj files using Ruby xcodeproj gem. Use when working with Xcode projects, adding new Swift/Objective-C files, or managing project references.
argument-hint: "[add|remove] [file-path] [--target target-name]"
---

# Xcode Project File Manager

Add and remove file references in `project.pbxproj` using the `xcodeproj` Ruby gem (same library CocoaPods uses).

## Prerequisites

```bash
gem install xcodeproj
```

## Quick usage

**Always run from the directory that contains the `.xcodeproj`** (project root).

```bash
# Add one file to the default/first target
ruby ~/.claude/skills/xcode-project/scripts/xcodeproj_helper.rb add "Top Music/Services/MyService.swift"

# Add to a specific target
ruby ~/.claude/skills/xcode-project/scripts/xcodeproj_helper.rb add "Top Music/Services/MyService.swift" --target "Top Music"

# Remove
ruby ~/.claude/skills/xcode-project/scripts/xcodeproj_helper.rb remove "Top Music/Services/MyService.swift"

# List targets
ruby ~/.claude/skills/xcode-project/scripts/xcodeproj_helper.rb list
```

## Critical rule — file reference paths

Xcode groups already carry directory prefixes (`path = Services` inside `path = "Top Music"`).

When adding a file reference, **store only the basename** in `PBXFileReference.path`:

| Correct | Wrong (duplicates path) |
|---------|-------------------------|
| `path = TMAdGate.swift` in `Services` group | `path = "Top Music/Services/TMAdGate.swift"` in `Services` group |

Wrong paths compile as missing files:

```
Top Music/Services/Top Music/Services/TMAdGate.swift
```

The helper script enforces this by calling `group.new_file(File.basename(file_path))` and verifies the resolved `real_path` after save.

## Agent workflow

### 1. Locate project root

```bash
find . -maxdepth 2 -name "*.xcodeproj" ! -name "Pods.xcodeproj"
cd /path/to/project/root   # directory containing MyApp.xcodeproj
```

### 2. Confirm gem is installed

```bash
ruby -e "require 'xcodeproj'; puts 'OK'" 2>/dev/null || gem install xcodeproj
```

### 3. Add files with the helper script

Pass the **disk path relative to project root** (same path you used when creating the file on disk):

```bash
ruby ~/.claude/skills/xcode-project/scripts/xcodeproj_helper.rb add "Top Music/Services/TMAdNavigationGate.swift" --target "Top Music"
```

For multiple files, call the script once per file (or loop in shell).

### 4. Verify

The helper exits non-zero if the saved reference resolves to the wrong on-disk path.

Also inspect the diff:

```bash
git diff *.xcodeproj/project.pbxproj
```

Confirm new `PBXFileReference` entries use **basename only**:

```text
path = TMAdNavigationGate.swift;   // good
path = "Top Music/Services/TMAdNavigationGate.swift";   // bad
```

### 5. Build

After adding sources, run an iOS build to confirm Xcode finds the files.

## How group resolution works

Given `Top Music/Services/Foo.swift`:

1. Parent directory → `Top Music/Services`
2. Find existing `PBXGroup` whose `real_path` matches that folder (walks the group tree)
3. If missing, create nested groups under `main_group` one component at a time
4. Add `Foo.swift` (basename only) to that group
5. Add the file reference to the target's `Sources` build phase

## Inline Ruby (only if script unavailable)

Do **not** pass the full file path to `group.new_file`. Match existing references in the project:

```ruby
require 'xcodeproj'

project_path = 'Top Music.xcodeproj'
file_path = 'Top Music/Services/TMAdNavigationGate.swift'
target_name = 'Top Music'

project = Xcodeproj::Project.open(project_path)
relative_dir = File.dirname(file_path)
filename = File.basename(file_path)

# Find group by on-disk location
abs_dir = File.expand_path(relative_dir)
group = nil
project.main_group.recursive_children.each do |child|
  next unless child.is_a?(Xcodeproj::Project::Object::PBXGroup)
  next unless child.real_path
  if File.expand_path(child.real_path.to_s) == abs_dir
    group = child
    break
  end
end

# Fallback: walk/create groups by name
unless group
  group = project.main_group
  relative_dir.split('/').reject(&:empty?).each do |part|
    group = group[part] || group.new_group(part, part)
  end
end

file_ref = group.new_file(filename)   # basename only — never file_path

target = project.targets.find { |t| t.name == target_name }
target.add_file_references([file_ref])

project.save
```

## Remove file

Prefer the helper script. It matches by resolved `real_path`, full relative path, or basename.

## Error handling

| Problem | Action |
|---------|--------|
| Project not found | `cd` to directory containing `.xcodeproj` or pass `--project` |
| Target not found | Run `list`; retry with `--target` |
| Verify failed after add | Check `PBXFileReference.path` in pbxproj — likely full path was used |
| File not on disk | Create the Swift file first, then add to project |

## Notes

- File paths are relative to the **project root** (parent of `.xcodeproj`), not the repo root unless they coincide.
- The helper skips duplicate adds when the basename already exists in the target group.
- Changes are saved immediately (`project.save`).
