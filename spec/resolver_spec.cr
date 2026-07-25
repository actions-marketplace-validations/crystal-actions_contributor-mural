require "./spec_helper"

private def config_from(yaml : String) : HallOfFame::Config
  HallOfFame::Config.from_yaml(yaml)
end

private def api_user(login : String, weight : Int32 = 1, avatar_url : String? = nil) : HallOfFame::ResolvedUser
  HallOfFame::ResolvedUser.new(login: login, avatar_url: avatar_url, weight: weight)
end

describe HallOfFame::Resolver do
  it "resolves list users with defaults" do
    config = config_from(<<-YAML)
      sort: none
      users:
        - login: hahwul
        - login: octocat
          name: The Octocat
          link: https://example.com
      YAML

    users = HallOfFame::Resolver.resolve(config)
    users.map(&.login).should eq(["hahwul", "octocat"])
    users[0].name.should eq("hahwul")
    users[0].link.should eq("https://github.com/hahwul")
    users[0].weight.should eq(1)
    users[1].name.should eq("The Octocat")
    users[1].link.should eq("https://example.com")
  end

  it "sorts by weight descending with login tie-break" do
    config = config_from(<<-YAML)
      users:
        - login: bravo
          weight: 2
        - login: Alpha
          weight: 2
        - login: charlie
          weight: 9
      YAML

    users = HallOfFame::Resolver.resolve(config)
    users.map(&.login).should eq(["charlie", "Alpha", "bravo"])
  end

  it "sorts by login when requested" do
    config = config_from(<<-YAML)
      sort: login
      users:
        - login: bravo
        - login: Alpha
      YAML

    HallOfFame::Resolver.resolve(config).map(&.login).should eq(["Alpha", "bravo"])
  end

  it "applies exclude and limit" do
    config = config_from(<<-YAML)
      sort: none
      exclude: [Bravo]
      limit: 1
      users:
        - login: alpha
        - login: bravo
        - login: charlie
      YAML

    HallOfFame::Resolver.resolve(config).map(&.login).should eq(["alpha"])
  end

  it "merges API data into list entries, config fields winning" do
    config = config_from(<<-YAML)
      source: both
      sort: none
      users:
        - login: hahwul
          name: HAHWUL
      YAML

    api = [api_user("HAHWUL", weight: 42, avatar_url: "https://avatars.example/1"), api_user("newcomer", weight: 3)]
    users = HallOfFame::Resolver.resolve(config, api)

    users.map(&.login).should eq(["hahwul", "newcomer"])
    users[0].name.should eq("HAHWUL")
    users[0].weight.should eq(42)
    users[0].avatar_url.should eq("https://avatars.example/1")
    users[1].weight.should eq(3)
  end

  it "uses only API users for source contributors" do
    config = config_from(<<-YAML)
      source: contributors
      sort: none
      users:
        - login: ignored
      YAML

    api = [api_user("worker")]
    HallOfFame::Resolver.resolve(config, api).map(&.login).should eq(["worker"])
  end
end
