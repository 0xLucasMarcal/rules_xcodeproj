def _custom_toolchain_impl(ctx):
    toolchain_dir = ctx.actions.declare_directory(ctx.attr.toolchain_name + ".xctoolchain")
    toolchain_info_plist_file = ctx.actions.declare_file(ctx.attr.toolchain_name + "_ToolchainInfo.plist")
    info_plist_file = ctx.actions.declare_file(ctx.attr.toolchain_name + "_Info.plist")

    default_toolchain_path = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"

    # Generate symlink creation commands dynamically, excluding ToolchainInfo.plist
    symlink_script = """#!/bin/bash
set -e

mkdir -p "{toolchain_dir}"

find "{default_toolchain}" -type f -o -type l | while read file; do
    rel_path="${{file#"{default_toolchain}/"}}"
    if [[ "$rel_path" != "ToolchainInfo.plist" && "$rel_path" != "Info.plist" ]]; then
        mkdir -p "{toolchain_dir}/$(dirname "$rel_path")"
        ln -s "$file" "{toolchain_dir}/$rel_path"
    fi
done

mkdir -p "{toolchain_dir}"
mv "{toolchain_info_plist}" "{toolchain_dir}/ToolchainInfo.plist"
mv "{info_plist}" "{toolchain_dir}/Info.plist"
""".format(
        toolchain_dir=toolchain_dir.path,
        default_toolchain=default_toolchain_path,
        toolchain_info_plist=toolchain_info_plist_file.path,
        info_plist=info_plist_file.path
    )

    script_file = ctx.actions.declare_file(ctx.attr.toolchain_name + "_setup.sh")
    ctx.actions.write(output=script_file, content=symlink_script, is_executable=True)

    # Generate ToolchainInfo.plist separately
    toolchain_info_plist_content = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Identifier</key>
    <string>com.example.{name}</string>
    <key>DisplayName</key>
    <string>{name}</string>
    <key>CompatibilityVersion</key>
    <string>9999</string>
</dict>
</plist>
""".format(name=ctx.attr.toolchain_name)

    ctx.actions.write(output=toolchain_info_plist_file, content=toolchain_info_plist_content)

    # Generate Info.plist
    info_plist_content = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.example.{name}</string>
    <key>CFBundleName</key>
    <string>{name}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>DTSDKName</key>
    <string>macosx</string>
    <key>DTSDKBuild</key>
    <string>9999</string>
    <key>DTCompiler</key>
    <string>com.apple.compilers.llvm.clang.1_0</string>
</dict>
</plist>
""".format(name=ctx.attr.toolchain_name)

    ctx.actions.write(output=info_plist_file, content=info_plist_content)

    # Run the generated shell script
    ctx.actions.run_shell(
        outputs=[toolchain_dir],
        inputs=[toolchain_info_plist_file, info_plist_file],
        tools=[script_file],
        command=script_file.path
    )

    return [DefaultInfo(files=depset([toolchain_dir]))]

custom_toolchain = rule(
    implementation=_custom_toolchain_impl,
    attrs={
        "toolchain_name": attr.string(mandatory=True),
    },
)
