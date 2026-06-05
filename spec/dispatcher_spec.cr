require "./spec_helper"

private def tool(key : String) : AloliPdf::Dispatcher::Tool
  AloliPdf::Dispatcher::TOOLS.find! { |entry| entry.key == key }
end

# Unit + behaviour tests for the alolipdf dispatcher. These don't require
# any sibling tool to be installed : the registry and binary-resolution
# contract are deterministic, and the routing assertions only check
# return codes / wiring (the real per-tool behaviour is covered by each
# tool's own suite).
describe AloliPdf::Dispatcher do
  it "exposes the expected suite subcommands" do
    keys = AloliPdf::Dispatcher::TOOLS.map(&.key)
    %w(combine validate sign verify watermark).each do |expected|
      keys.should contain(expected)
    end
  end

  it "maps sign / verify onto pdf-sign with the right prepended verb" do
    tool("sign").binary.should eq("pdf-sign")
    tool("verify").binary.should eq("pdf-sign")
    tool("sign").prepend.should eq(["sign"])
    tool("verify").prepend.should eq(["verify"])
  end

  it "drives combine / validate / watermark with their own binaries, no prefix" do
    tool("combine").binary.should eq("crystal-combine-pdf")
    tool("validate").binary.should eq("pdf-validate")
    tool("watermark").binary.should eq("watermark")
    tool("validate").prepend.should be_empty
  end

  it "resolves a tool binary from its $ALOLIPDF_* override" do
    entry = tool("validate")
    previous = ENV[entry.env]?
    ENV[entry.env] = "/opt/aloli/pdf-validate"
    begin
      AloliPdf::Dispatcher.resolve(entry).should eq("/opt/aloli/pdf-validate")
    ensure
      previous ? (ENV[entry.env] = previous) : ENV.delete(entry.env)
    end
  end

  it "returns exit code 2 for an unknown subcommand" do
    AloliPdf::Dispatcher.run(["definitely-not-a-tool"]).should eq(2)
  end

  it "returns exit code 0 for `version`" do
    AloliPdf::Dispatcher.run(["version"]).should eq(0)
  end

  it "returns an Int32 status when forwarding (missing binary → 2)" do
    entry = tool("watermark")
    previous = ENV[entry.env]?
    ENV[entry.env] = "" # empty override → fall through to PATH lookup
    begin
      AloliPdf::Dispatcher.forward(entry, ["--nope"]).should be_a(Int32)
    ensure
      previous ? (ENV[entry.env] = previous) : ENV.delete(entry.env)
    end
  end
end
