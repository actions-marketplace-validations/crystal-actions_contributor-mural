require "file_utils"
require "./spec_helper"
require "./support/fake_avatar_source"
require "./support/fake_github_source"
require "./support/fake_rasterizer"

private def run_in_tmp(config_yaml : String, source = FakeAvatarSource.new,
                       github_source : HallOfFame::GitHubSource? = nil,
                       rasterizer : HallOfFame::Rasterizer? = nil,
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
    exit_code = HallOfFame::Runner.new(config, source, workspace, github_source, nil, rasterizer).run
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
    github_source = FakeGitHubSource.new(api_users)

    run_in_tmp(yaml, github_source: github_source) do |exit_code, outputs, workspace|
      exit_code.should eq(0)
      github_source.requested_repos.should eq(["hahwul/hall-of-fame"])
      outputs.should contain("user_count=2")
      svg = File.read(File.join(workspace, "HALL_OF_FAME.svg"))
      svg.should contain(%(href="https://github.com/contributor"))
    end
  end

  it "rasterizes .png outputs with a static light palette" do
    yaml = <<-YAML
      outputs:
        - path: wall.svg
        - path: wall.png
        - path: wall-dark.png
          mode: dark
      users:
        - login: alpha
      YAML

    rasterizer = FakeRasterizer.new
    run_in_tmp(yaml, rasterizer: rasterizer) do |exit_code, outputs, workspace|
      exit_code.should eq(0)
      String.new(File.read(File.join(workspace, "wall.png")).to_slice).should eq("FAKEPNG@2.0")
      rasterizer.calls.size.should eq(2)
      light_svg = rasterizer.calls[0][0]
      light_svg.should_not contain("<style>")
      light_svg.should contain(%(fill="#57606a"))
      dark_svg = rasterizer.calls[1][0]
      dark_svg.should contain(%(fill="#8b949e"))
      File.read(File.join(workspace, "wall.svg")).should contain("<style>")
      outputs.should contain("svg_path=wall.svg,wall.png,wall-dark.png")
    end
  end

  it "fails cleanly when a png is requested without a rasterizer" do
    yaml = <<-YAML
      output: wall.png
      users:
        - login: alpha
      YAML

    run_in_tmp(yaml) do |exit_code, _outputs, _workspace|
      exit_code.should eq(1)
      HallOfFame::Annotations.io.to_s.should contain("no rasterizer")
    end
  end

  it "combines members, stargazers, and sponsors into their groups" do
    yaml = <<-YAML
      groups: [Team, Stars, Sponsors]
      users:
        - login: hahwul
      members:
        org: crystal-actions
        group: Team
      stargazers:
        repo: crystal-actions/hall-of-fame
        group: Stars
      sponsors:
        login: hahwul
        group: Sponsors
      YAML

    github_source = FakeGitHubSource.new(
      members: [HallOfFame::ResolvedUser.new("teammate", group: "Team")],
      stargazers: [HallOfFame::ResolvedUser.new("fan", group: "Stars")],
      sponsors: [HallOfFame::ResolvedUser.new("patron", weight: 25, group: "Sponsors")],
    )

    run_in_tmp(yaml, github_source: github_source) do |exit_code, outputs, workspace|
      exit_code.should eq(0)
      github_source.requested_orgs.should eq(["crystal-actions"])
      github_source.requested_star_repos.should eq(["crystal-actions/hall-of-fame"])
      github_source.requested_sponsor_logins.should eq(["hahwul"])
      outputs.should contain("user_count=4")
      svg = File.read(File.join(workspace, "HALL_OF_FAME.svg"))
      svg.should contain(">Team</text>")
      svg.should contain(">Stars</text>")
      svg.should contain(">Sponsors</text>")
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
      HallOfFame::Annotations.io.to_s.should contain("::error::the configured sources need GitHub API access")
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
