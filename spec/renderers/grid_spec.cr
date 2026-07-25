require "../spec_helper"
require "../support/fake_avatar_source"
require "../support/golden"

private def render(config : HallOfFame::Config) : String
  users = HallOfFame::Resolver.resolve(config)
  renderer = HallOfFame::Renderer.for(config.style, config)
  embedded, _ = HallOfFame::Embedder.new(FakeAvatarSource.new)
    .embed(users, renderer, fail_on_missing: false)
  renderer.render(embedded)
end

private GOLDEN_USERS = <<-YAML
  sort: none
  users:
    - login: hahwul
      name: HAHWUL
    - login: octocat
      name: The Octocat
    - login: long-name-user
      name: An Extremely Long Display Name
    - login: escaper
      name: "R&D <Team>"
    - login: hangul
      name: 한글이름
    - login: plain
  YAML

describe HallOfFame::Renderers::Grid do
  it "renders the circle grid golden file" do
    config = HallOfFame::Config.from_yaml(<<-YAML)
      #{GOLDEN_USERS}
      grid:
        columns: 4
        avatar_size: 64
        margin: 8
        shape: circle
        show_names: true
        truncate: 12
      YAML

    svg = render(config)
    svg.should contain(%(width="296" height="188"))
    svg.should contain("data:image/png;base64,")
    svg.should contain(%(clip-path="url(#avatar-clip)"))
    svg.should contain("R&amp;D &lt;Team&gt;")
    svg.should contain("An Extremel…")
    Golden.assert("grid_circle.svg", svg)
  end

  it "renders the square label-less golden file" do
    config = HallOfFame::Config.from_yaml(<<-YAML)
      #{GOLDEN_USERS}
      theme:
        background: "#0d1117"
      grid:
        columns: 6
        avatar_size: 48
        margin: 4
        shape: square
        show_names: false
      YAML

    svg = render(config)
    svg.should_not contain("clip-path")
    svg.should_not contain("<text")
    svg.should contain(%(<rect width="100%" height="100%" fill="#0d1117"/>))
    Golden.assert("grid_square.svg", svg)
  end

  it "links every avatar to the user's page" do
    config = HallOfFame::Config.from_yaml(GOLDEN_USERS)
    svg = render(config)
    svg.scan(/<a href=/).size.should eq(6)
    svg.should contain(%(href="https://github.com/hahwul"))
  end

  it "renders an empty document without users" do
    config = HallOfFame::Config.from_yaml("source: contributors")
    svg = HallOfFame::Renderer.for(HallOfFame::Style::Grid, config)
      .render([] of HallOfFame::EmbeddedUser)
    svg.should contain("<svg")
    svg.should_not contain("<image")
  end
end
