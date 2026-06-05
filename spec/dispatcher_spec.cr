require "./spec_helper"

private def tool(key : String) : AloliPdf::Dispatcher::Tool
  AloliPdf::Dispatcher::TOOLS.find! { |entry| entry.key == key }
end

# Unit + behaviour tests for the alolipdf megabinary dispatcher. The ALOLI
# tools are compiled in (called in-process); poppler's info/fonts stay
# external shell-outs. Per-tool behaviour is covered by each tool's own
# suite — here we pin the registry shape and routing contract.
describe AloliPdf::Dispatcher do
  it "exposes the expected suite subcommands" do
    keys = AloliPdf::Dispatcher::TOOLS.map(&.key)
    %w(combine validate sign verify watermark info fonts).each do |expected|
      keys.should contain(expected)
    end
  end

  it "compiles the ALOLI tools in-process (a runner, no external binary)" do
    %w(combine validate sign verify watermark).each do |key|
      tool(key).runner.should_not be_nil
      tool(key).binary.should be_nil
    end
  end

  it "keeps poppler info/fonts as external shell-outs (a binary, no runner)" do
    tool("info").runner.should be_nil
    tool("info").binary.should eq("pdfinfo")
    tool("fonts").runner.should be_nil
    tool("fonts").binary.should eq("pdffonts")
  end

  it "resolves an external tool from its $ALOLIPDF_* override" do
    entry = tool("info")
    env = entry.env
    env.should_not be_nil
    if env
      previous = ENV[env]?
      ENV[env] = "/opt/poppler/pdfinfo"
      begin
        AloliPdf::Dispatcher.resolve(entry).should eq("/opt/poppler/pdfinfo")
      ensure
        previous ? (ENV[env] = previous) : ENV.delete(env)
      end
    end
  end

  it "runs an ALOLI tool in-process (validate -v returns 0)" do
    AloliPdf::Dispatcher.dispatch(tool("validate"), ["-v"]).should eq(0)
  end

  it "returns exit code 2 for an unknown subcommand" do
    AloliPdf::Dispatcher.run(["definitely-not-a-tool"]).should eq(2)
  end

  it "returns exit code 0 for `version`" do
    AloliPdf::Dispatcher.run(["version"]).should eq(0)
  end
end
