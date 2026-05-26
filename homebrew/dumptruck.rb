cask "dumptruck" do
  version "1.0.0"
  sha256 "fde3321521c71720604dc21fc230990dc716401225914747ac2aab8c279091c8"

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
