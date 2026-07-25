require "file_utils"
require "./spec_helper"
require "./support/fake_avatar_source"
require "./support/fake_contributor_source"

private def run_in_tmp(config_yaml : String, source = FakeAvatarSource.new,
                       contributor_source : HallOfFame::ContributorSource? = nil,
                       & : Int32, String, String ->)
  workspace = File.tempname("hof_ws")
  Dir.mkdir_p(workspace)
  output_file = File.tempname("gh_output")
  annotations = IO::Memory.new
  HallOfFame::Annotations.io = annotations
  ENV["GITHUB_OUTPUT"] = output_file
  begin
    config = HallOfFame::Config.from_yaml(config_yaml)
    config.validate!
    exit_code = HallOfFame::Runner.new(config, source, workspace, contributor_source).run
    outputs = File.exists?(output_file) ? File.read(output_file) : ""
    yield exit_code, outputs, workspace
  ensure
    HallOfFame::Annotations.io = STDOUT
    ENV.delete("GITHUB_OUTPUT")
    File.delete?(output_file)
    FileUtils.rm_rf(workspace)
  end
end

describe HallOfFame::Runner do
  it "writes the SVG and step outputs" do
    yaml = <<-YAML
      output: art/wall.svg
      users:
        - login: alpha
        - login: bravo
      YAML

    run_in_tmp(yaml) do |exit_code, outputs, workspace|
      exit_code.should eq(0)
      svg = File.read(File.join(workspace, "art/wall.svg"))
      svg.should contain("data:image/png;base64,")
      outputs.should contain("svg_path=art/wall.svg")
      outputs.should contain("user_count=2")
    end
  end

  it "renders multiple outputs reusing fetches" do
    yaml = <<-YAML
      outputs:
        - path: one.svg
        - path: two.svg
      users:
        - login: alpha
      YAML

    source = FakeAvatarSource.new
    run_in_tmp(yaml, source) do |exit_code, outputs, workspace|
      exit_code.should eq(0)
      File.exists?(File.join(workspace, "one.svg")).should be_true
      File.exists?(File.join(workspace, "two.svg")).should be_true
      source.fetch_count.should eq(1)
      outputs.should contain("svg_path=one.svg,two.svg")
    end
  end

  it "warns and continues when an avatar is missing" do
    yaml = <<-YAML
      users:
        - login: alpha
        - login: gone
      YAML

    run_in_tmp(yaml, FakeAvatarSource.new(missing: ["gone"])) do |exit_code, outputs, _workspace|
      exit_code.should eq(0)
      HallOfFame::Annotations.io.to_s.should contain("::warning::skipped gone")
      outputs.should contain("user_count=1")
    end
  end

  it "merges contributors from the API source" do
    yaml = <<-YAML
      source: both
      contributors:
        repo: hahwul/hall-of-fame
      users:
        - login: hahwul
          weight: 99
      YAML

    api_users = [
      HallOfFame::ResolvedUser.new("contributor", weight: 5),
      HallOfFame::ResolvedUser.new("hahwul", weight: 1),
    ]
    contributor_source = FakeContributorSource.new(api_users)

    run_in_tmp(yaml, contributor_source: contributor_source) do |exit_code, outputs, workspace|
      exit_code.should eq(0)
      contributor_source.requested_repos.should eq(["hahwul/hall-of-fame"])
      outputs.should contain("user_count=2")
      svg = File.read(File.join(workspace, "HALL_OF_FAME.svg"))
      svg.should contain(%(href="https://github.com/contributor"))
    end
  end

  it "fails cleanly when contributors are requested without API access" do
    yaml = <<-YAML
      source: contributors
      contributors:
        repo: hahwul/hall-of-fame
      YAML

    run_in_tmp(yaml) do |exit_code, _outputs, _workspace|
      exit_code.should eq(1)
      HallOfFame::Annotations.io.to_s.should contain("::error::source 'contributors' needs GitHub API access")
    end
  end

  it "fails when fail_on_missing is set" do
    yaml = <<-YAML
      fail_on_missing: true
      users:
        - login: gone
      YAML

    run_in_tmp(yaml, FakeAvatarSource.new(missing: ["gone"])) do |exit_code, _outputs, _workspace|
      exit_code.should eq(1)
      HallOfFame::Annotations.io.to_s.should contain("::error::gone")
    end
  end
end
