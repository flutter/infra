#!/usr/bin/env lucicfg
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
Configurations for packaging builders.

The schedulers pull commits indirectly from GoB repo (https://chromium.googlesource.com/external/github.com/flutter/flutter)
which is mirrored from https://github.com/flutter/flutter.
"""

load("//lib/common.star", "common")
load("//lib/repos.star", "repos")

# Global OS variables
LINUX_OS = "Linux"
WINDOWS_OS = "Windows-Server"
MAC_OS = "Mac-10.15"

# Linux caches
LINUX_DEFAULT_CACHES = [
    # Android SDK
    swarming.cache(name = "android_sdk", path = "android"),
    # Chrome
    swarming.cache(name = "chrome_and_driver", path = "chrome"),
    # OpenJDK
    swarming.cache(name = "openjdk", path = "java"),
    # PubCache
    swarming.cache(name = "pub_cache", path = ".pub-cache"),
    # Flutter SDK code
    swarming.cache(name = "flutter_sdk", path = "flutter sdk"),
]

def _setup(branches):
    platform_args = {
        "linux": {
            "properties": {
                "shard": "framework_tests",
            },
            "os": LINUX_OS,
        },
        "mac": {
            "properties": {
                "shard": "framework_tests",
            },
            "os": MAC_OS,
        },
        "windows": {
            "properties": {
                "shard": "framework_tests",
            },
            "os": WINDOWS_OS,
        },
    }

    packaging_recipe("ios-usb-dependencies", "")

    packaging_recipe("flutter", branches.stable.version)
    packaging_prod_config(
        platform_args,
        "stable",
        branches.stable.version,
        branches.stable.release_ref,
    )

    packaging_recipe("flutter", branches.beta.version)
    packaging_prod_config(
        platform_args,
        "beta",
        branches.beta.version,
        branches.beta.release_ref,
    )

    packaging_recipe("flutter", branches.dev.version)
    packaging_prod_config(
        platform_args,
        "dev",
        branches.dev.version,
        branches.dev.release_ref,
    )

    packaging_prod_config(
        platform_args,
        "master",
        branches.master.version,
        # Note for master, there is no distinction between testing_ref &
        # release_ref
        "refs/heads/master",
    )

def recipe_name(name, version):
    return "%s%s" % (name, "_%s" % version if version else "")

def builder_name(pattern, branch):
    return pattern % (branch.capitalize(), branch)

def packaging_recipe(name, version):
    luci.recipe(
        name = recipe_name(name, version),
        cipd_package = "flutter/recipe_bundles/flutter.googlesource.com/recipes",
        cipd_version = "refs/heads/master",
        use_bbagent = True,
    )

def packaging_prod_config(platform_args, branch, version, ref):
    """Prod configurations for packaging flutter framework artifacts.

    Args:
      platform_args(dict): Dictionary with default properties with platform as
        key.
      branch(str): The branch name we are creating configurations for.
      version(str): One of dev|beta|stable.
      ref(str): The git ref we are creating configurations for.
    """

    # Defines console views for prod builders
    console_view_name = ("packaging" if branch == "master" else "%s_packaging" % branch)
    luci.console_view(
        name = console_view_name,
        repo = repos.FLUTTER,
        refs = [ref],
    )

    # Defines prod schedulers
    trigger_name = branch + "-gitiles-trigger-packaging"
    luci.gitiles_poller(
        name = trigger_name,
        bucket = "prod",
        repo = repos.FLUTTER,
        refs = [ref],
    )

    # Defines triggering policy
    if branch == "master":
        triggering_policy = scheduler.greedy_batching(
            max_concurrent_invocations = 6,
        )
    else:
        triggering_policy = scheduler.greedy_batching(
            max_concurrent_invocations = 3,
        )

    # Select which firebase project to upload the docs to.
    firebase_project = ""
    if branch == "master":
        firebase_project = "master-docs-flutter-dev"
    if branch == "stable":
        firebase_project = "docs-flutter-dev"

    # Docs builds are only done on master and stable channels
    if branch in ("master", "stable"):
        common.linux_prod_builder(
            name = "Linux%s docs_publish|docs" % ("" if branch == "master" else " " + branch),
            recipe = "flutter/flutter%s" % ("" if branch == "master" else "_" + version),
            console_view_name = console_view_name,
            triggered_by = [trigger_name],
            triggering_policy = triggering_policy,
            properties = {
                "validation": "docs",
                "validation_name": "Docs",
                "dependencies": [{"dependency": "dashing"}, {"dependency": "firebase"}, {"dependency": "curl"}],
                "firebase_project": firebase_project,
                # This determines which release channel docs to deploy
                "release_ref": ref,
            },
            caches = LINUX_DEFAULT_CACHES,
            os = LINUX_OS,
        )

    # Packaging should only build from release branches and never from master. This
    # is to prevent using excesive amount of resources to package something we will
    # never use.
    if branch in ("dev", "beta", "stable"):
        # Defines framework prod builders
        common.linux_prod_builder(
            name = builder_name("Linux Flutter %s Packaging|%s", branch),
            recipe = recipe_name("flutter", version),
            console_view_name = console_view_name,
            triggered_by = [trigger_name],
            triggering_policy = triggering_policy,
            priority = 30 if branch == "master" else 25,
            **platform_args["linux"]
        )
        common.mac_prod_builder(
            name = builder_name("Mac Flutter %s Packaging|%s", branch),
            recipe = recipe_name("flutter", version),
            console_view_name = console_view_name,
            triggered_by = [trigger_name],
            triggering_policy = triggering_policy,
            priority = 30 if branch == "master" else 25,
            **platform_args["mac"]
        )
        common.windows_prod_builder(
            name = builder_name("Windows Flutter %s Packaging|%s", branch),
            recipe = recipe_name("flutter", version),
            console_view_name = console_view_name,
            triggered_by = [trigger_name],
            triggering_policy = triggering_policy,
            priority = 30 if branch == "master" else 25,
            **platform_args["windows"]
        )

packaging_config = struct(setup = _setup)
