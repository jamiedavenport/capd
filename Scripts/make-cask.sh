#!/bin/sh
# Emits the Homebrew cask for a release: make-cask.sh <version> <dmg-sha256>.
# The release workflow writes the output to Casks/capd.rb in the tap.

set -eu

VERSION=$1
SHA256=$2

cat <<EOF
cask "capd" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/jamiedavenport/capd/releases/download/v#{version}/capd-#{version}.dmg"
  name "Capd"
  desc "Menu-bar capture and search for things you've seen"
  homepage "https://github.com/jamiedavenport/capd"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "capd.app"
  binary "#{appdir}/capd.app/Contents/MacOS/capd"

  uninstall launchctl: "dev.jxd.capd.agent",
            quit:      "dev.jxd.capd"

  zap trash: [
    "~/Library/Application Support/capd",
    "~/Library/LaunchAgents/dev.jxd.capd.agent.plist",
  ]
end
EOF
