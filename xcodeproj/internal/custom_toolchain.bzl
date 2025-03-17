def _custom_toolchain_impl(ctx):
    toolchain_dir = ctx.actions.declare_directory(ctx.attr.toolchain_name + ".xctoolchain")
    toolchain_plist_file = ctx.actions.declare_file(ctx.attr.toolchain_name + "_ToolchainInfo.plist")

    default_toolchain_path = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
    user_toolchain_path = "$(eval echo ~)/Library/Developer/Toolchains/{}.xctoolchain".format(ctx.attr.toolchain_name)
    built_toolchain_path = "$(eval pwd)/"+toolchain_dir.path

    # Generate symlink creation commands dynamically, excluding plist files
    symlink_script = """#!/bin/bash
set -e

mkdir -p "{toolchain_dir}"

find "{default_toolchain}" -type f -o -type l | while read file; do
    base_name="$(basename "$file")"
    rel_path="${{file#"{default_toolchain}/"}}"
    
    override_path="$(echo {overrides} | jq -r --arg key "$base_name" '.[$key] // empty')"
    if [[ -f "$override_path" ]]; then
        mkdir -p "{toolchain_dir}/$(dirname "$rel_path")"
        cp "$override_path" "{toolchain_dir}/$rel_path"
        continue
    fi
    
    if [[ "$rel_path" != "ToolchainInfo.plist" ]]; then
        mkdir -p "{toolchain_dir}/$(dirname "$rel_path")"
        ln -s "$file" "{toolchain_dir}/$rel_path"
    fi
done

mv "{toolchain_plist}" "{toolchain_dir}/ToolchainInfo.plist"

# Remove existing symlink if present and create a new one in the user directory
if [ -e "{user_toolchain_path}" ]; then
    rm -f "{user_toolchain_path}"
fi
ln -s "{built_toolchain_path}" "{user_toolchain_path}"
""".format(
        toolchain_dir=toolchain_dir.path,
        default_toolchain=default_toolchain_path,
        overrides=ctx.attr.overrides,
        toolchain_plist=toolchain_plist_file.path,
        user_toolchain_path=user_toolchain_path,
        built_toolchain_path=built_toolchain_path
    )

    script_file = ctx.actions.declare_file(ctx.attr.toolchain_name + "_setup.sh")
    ctx.actions.write(output=script_file, content=symlink_script, is_executable=True)

    # Generate ToolchainInfo.plist
    toolchain_plist_content = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Aliases</key>
    <array>
      <string>{name}</string>
    </array>
    <key>CFBundleIdentifier</key>
    <string>com.example.{name}</string>
    <key>CompatibilityVersion</key>
    <integer>2</integer>
    <key>CompatibilityVersionDisplayString</key>
    <string>Xcode 13.0</string>
    <key>DisplayName</key>
    <string>{name}</string>
    <key>ReportProblemURL</key>
    <string>https://github.com/MobileNativeFoundation/rules_xcodeproj</string>
    <key>ShortDisplayName</key>
    <string>{name}</string>
    <key>Version</key>
    <string>0.0.1</string>
  </dict>
</plist>
""".format(name=ctx.attr.toolchain_name)

    ctx.actions.write(output=toolchain_plist_file, content=toolchain_plist_content)

    # Run the generated shell script
    ctx.actions.run_shell(
        outputs=[toolchain_dir],
        inputs=[toolchain_plist_file],
        tools=[script_file],
        command=script_file.path
    )

    return [DefaultInfo(files=depset([toolchain_dir]))]

custom_toolchain = rule(
    implementation=_custom_toolchain_impl,
    attrs={
        "toolchain_name": attr.string(mandatory=True),
        "overrides": attr.string_dict(default={}),
    },
)

