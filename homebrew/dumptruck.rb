cask "dumptruck" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_FROM_MAKE_DMG"

  url "https://github.com/matchavez/dumptruck/releases/download/v#{version}/Dumptruck-#{version}.dmg"
  name "Dumptruck"
  desc "Quick-capture menubar app — jot a note instantly from any context"
  homepage "https://github.com/matchavez/dumptruck"

  depends_on macos: ">= :sonoma"

  app "Dumptruck.app"

  zap trash: [
    "~/Library/Application Support/Dumptruck",
    "~/Library/Preferences/com.matchavez.Dumptruck.plist",
  ]
end
