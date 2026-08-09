load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_bundle")
load(":dual_aspect_tests.bzl", "dual_aspect_resource_bundle_test")

apple_resource_bundle(
    name = "RawResources",
    bundle_id = "com.example.rules-xcodeproj.dual-aspect",
    infoplists = ["Info.plist"],
    resources = glob(["Resources/**"]),
)

dual_aspect_resource_bundle_test(
    name = "dual_aspect_resource_bundle",
    target = ":RawResources",
)
