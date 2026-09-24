class Sparekey < Formula
  desc "Unlock and relock the current user's logged-in Mac for authorized agent computer use"
  homepage "https://github.com/yoonpooh/sparekey"
  url "https://github.com/yoonpooh/sparekey/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_SHA256"
  license "MIT"

  depends_on :macos => :ventura

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/sparekey"
  end

  def caveats
    <<~EOS
      Install Xcode Command Line Tools with Swift 5.9 or newer, then run
      `sparekey setup` locally in an interactive terminal while unlocked.
      Setup signs a stable helper copy and asks which agent skills to install.
    EOS
  end

  test do
    assert_match "sparekey 0.2.0", shell_output("#{bin}/sparekey --version")
    assert_match "Usage:", shell_output("#{bin}/sparekey --help")
  end
end
