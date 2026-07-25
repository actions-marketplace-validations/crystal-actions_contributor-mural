require "./spec_helper"

describe HallOfFame::Annotations do
  around_each do |example|
    io = IO::Memory.new
    HallOfFame::Annotations.io = io
    example.run
  ensure
    HallOfFame::Annotations.io = STDOUT
  end

  it "emits error annotations with file and line" do
    HallOfFame::Annotations.error("boom", file: "conf.yml", line: 3)
    HallOfFame::Annotations.io.to_s.should eq("::error file=conf.yml,line=3::boom\n")
  end

  it "emits plain warnings" do
    HallOfFame::Annotations.warning("careful")
    HallOfFame::Annotations.io.to_s.should eq("::warning::careful\n")
  end

  it "escapes newlines and percent signs in messages" do
    HallOfFame::Annotations.error("a%b\nc")
    HallOfFame::Annotations.io.to_s.should eq("::error::a%25b%0Ac\n")
  end

  it "escapes colons and commas in properties" do
    HallOfFame::Annotations.error("x", file: "a:b,c.yml")
    HallOfFame::Annotations.io.to_s.should eq("::error file=a%3Ab%2Cc.yml::x\n")
  end

  it "writes step outputs to GITHUB_OUTPUT" do
    path = File.tempname("gh_output")
    begin
      ENV["GITHUB_OUTPUT"] = path
      HallOfFame::Annotations.output("svg_path", "HALL_OF_FAME.svg")
      HallOfFame::Annotations.output("user_count", "7")
      File.read(path).should eq("svg_path=HALL_OF_FAME.svg\nuser_count=7\n")
    ensure
      ENV.delete("GITHUB_OUTPUT")
      File.delete?(path)
    end
  end

  it "ignores step outputs outside of GitHub Actions" do
    ENV.delete("GITHUB_OUTPUT")
    HallOfFame::Annotations.output("k", "v")
  end
end
