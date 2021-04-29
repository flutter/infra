#!/usr/bin/env lucicfg
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
Configurations for ios_tool builders.

The schedulers for ios_tool builds use GoB flutter mirrors
(https://flutter-mirrors.googlesource.com/).
"""

load("//lib/common.star", "common")
load("//lib/consoles.star", "consoles")
load("//lib/repos.star", "repos")

# Global OS variables
MAC_OS = "Mac-10.15"

def _setup():
    luci.recipe(
        name = "ios-usb-dependencies",
        cipd_package = "flutter/recipe_bundles/flutter.googlesource.com/recipes",
        cipd_version = "refs/heads/master",
        use_bbagent = True,
    )
    iostools_prod_config()

def ios_tools_builder(name, repo):
    """Creates configurations for ios tool builders.

    Args:
      name(str): The name of the tool repository.
      repo(str): The url of the repository.
    """
    builder = name.split("|")[0]
    consoles.console_view(builder, repo)
    luci.gitiles_poller(
        name = "gitiles-trigger-%s" % builder,
        bucket = "prod",
        repo = repo,
        triggers = [builder],
    )
    common.mac_prod_builder(
        name = name,
        repo = repo,
        recipe = "ios-usb-dependencies",
        properties = {
            "package_name": builder + "-flutter",
        },
        console_view_name = builder,
        triggering_policy = scheduler.greedy_batching(
            max_concurrent_invocations = 1,
        ),
        os = MAC_OS,
    )

def iostools_prod_config():
    """Creates prod configurations for iostools."""
    ios_tools_builder(
        name = "ideviceinstaller|idev",
        repo = repos.IDEVICEINSTALLER,
    )
    ios_tools_builder(
        name = "libimobiledevice|libi",
        repo = repos.LIBIMOBILEDEVICE,
    )
    ios_tools_builder(name = "libplist|plist", repo = repos.LIBPLIST)
    ios_tools_builder(name = "usbmuxd|usbmd", repo = repos.USBMUXD)
    ios_tools_builder(name = "openssl|ssl", repo = repos.OPENSSL)
    ios_tools_builder(name = "ios-deploy|deploy", repo = repos.IOS_DEPLOY)
    ios_tools_builder(name = "libzip|zip", repo = repos.LIBZIP)

iostools_config = struct(setup = _setup)
