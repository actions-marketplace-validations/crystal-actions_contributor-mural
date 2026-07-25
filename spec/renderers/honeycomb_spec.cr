require "../spec_helper"
require "../support/fake_avatar_source"
require "../support/golden"

private def render_honeycomb(config : HallOfFame::Config) : String
  users = HallOfFame::Resolver.resolve(config)
  renderer = HallOfFame::Renderer.for(HallOfFame::Style::Honeycomb, config)
  renderer.prepare(users)
  embedded, _ = HallOfFame::Embedder.new(FakeAvatarSource.new)
    .embed(users, renderer, fail_on_missing: false)
  renderer.render(embedded)
end

describe HallOfFame::Renderers::Honeycomb do
  it "renders the honeycomb golden file" do
    config = HallOfFame::Config.from_yaml(<<-YAML)
      style: honeycomb
      sort: none
      users:
        - login: one
        - login: two
        - login: three
        - login: four
        - login: five
        - login: six
        - login: seven
      honeycomb:
        columns: 3
        cell_size: 60
        gap: 4
      YAML

    svg = render_honeycomb(config)
    svg.should contain(%(<polygon points="0.5,0 1,0.25 1,0.75 0.5,1 0,0.75 0,0.25"/>))
    svg.should contain(%(clip-path="url(#hex-clip)"))
    Golden.assert("honeycomb.svg", svg)
  end

  it "offsets odd rows and reduces their capacity" do
    config = HallOfFame::Config.from_yaml(<<-YAML)
      style: honeycomb
      sort: none
      users:
        - login: r0c0
        - login: r0c1
        - login: r0c2
        - login: r1c0
        - login: r1c1
        - login: r2c0
      honeycomb:
        columns: 3
        cell_size: 60
        gap: 4
      YAML

    svg = render_honeycomb(config)
    # Row 0 starts at x=4; row 1 (odd, 2 items) shifts half a cell to x=36.
    svg.should contain(%(x="4" y="4"))
    svg.should contain(%(x="36" y="59.96"))
    # Row 2 returns to x=4 at double pitch.
    svg.should contain(%(x="4" y="115.92"))
  end

  it "fetches avatars at twice the cell size" do
    config = HallOfFame::Config.from_yaml("honeycomb:\n  cell_size: 60\nusers:\n  - login: x")
    renderer = HallOfFame::Renderer.for(HallOfFame::Style::Honeycomb, config)
    renderer.fetch_size(HallOfFame::ResolvedUser.new("x")).should eq(120)
  end
end
