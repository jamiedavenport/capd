#!/bin/sh
# Emits the Homebrew cask for a release: make-cask.sh <version> <dmg-sha256>.
# The release workflow writes the output to Casks/cap.rb in the tap.

set -eu

VERSION=$1
SHA256=$2

cat <<EOF
cask "cap" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/jamiedavenport/cap/releases/download/v#{version}/cap-#{version}.dmg"
  name "cap"
  desc "Menu-bar capture and search for things you've seen"
  homepage "https://github.com/jamiedavenport/cap"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "cap.app"
  binary "#{appdir}/cap.app/Contents/MacOS/cap"

  uninstall launchctl: "dev.jxd.cap.agent",
            quit:      "dev.jxd.cap"

  zap trash: [
    "~/Library/Application Support/cap",
    "~/Library/LaunchAgents/dev.jxd.cap.agent.plist",
  ]
end
EOF
