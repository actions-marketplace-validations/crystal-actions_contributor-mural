require "../spec_helper"
require "http/server"
require "json"

private def contributor_json(login : String, contributions : Int32, type : String = "User") : String
  {
    login:         login,
    avatar_url:    "https://avatars.example/#{login}",
    html_url:      "https://github.com/#{login}",
    contributions: contributions,
    type:          type,
  }.to_json
end

private ANON_JSON = {
  name:          "Ghost Writer",
  email:         "ghost@example.com",
  type:          "Anonymous",
  contributions: 7,
}.to_json

# Serves canned contributor pages and records request paths+headers.
private def with_api_server(pages : Hash(Int32, String), status : Int32 = 200,
                            headers : HTTP::Headers = HTTP::Headers.new, &)
  seen = [] of {String, String?}
  server = HTTP::Server.new do |context|
    seen << {"#{context.request.path}?#{context.request.query}", context.request.headers["Authorization"]?}
    if status != 200
      headers.each { |key, values| context.response.headers[key] = values }
      context.response.status_code = status
      next
    end
    page = (context.request.query_params["page"]? || "1").to_i
    context.response.content_type = "application/json"
    context.response.print(pages[page]? || "[]")
  end
  address = server.bind_unused_port "127.0.0.1"
  spawn { server.listen }
  begin
    yield "http://#{address}", seen
  ensure
    server.close
  end
end

private def options_from(yaml : String) : HallOfFame::ContributorsConfig
  HallOfFame::Config.from_yaml(yaml).contributors
end

describe HallOfFame::GitHubApi do
  it "maps contributors to users with contribution weights" do
    pages = {1 => "[#{contributor_json("alice", 42)},#{contributor_json("bob", 3)}]"}
    with_api_server(pages) do |base, _seen|
      api = HallOfFame::GitHubApi.new(api_base: base)
      users = api.contributors("owner/repo")
      users.map(&.login).should eq(["alice", "bob"])
      users[0].weight.should eq(42)
      users[0].avatar_url.should eq("https://avatars.example/alice")
      users[0].link.should eq("https://github.com/alice")
    end
  end

  it "filters bots by default and keeps them when asked" do
    pages = {1 => "[#{contributor_json("human", 5)},#{contributor_json("dependabot[bot]", 9, "Bot")}]"}
    with_api_server(pages) do |base, _seen|
      HallOfFame::GitHubApi.new(api_base: base)
        .contributors("o/r").map(&.login).should eq(["human"])

      options = options_from("contributors:\n  include_bots: true")
      HallOfFame::GitHubApi.new(options: options, api_base: base)
        .contributors("o/r").map(&.login).should eq(["human", "dependabot[bot]"])
    end
  end

  it "paginates until a short page" do
    first_page = (1..100).map { |index| contributor_json("user#{index}", 100 - index + 1) }.join(",")
    pages = {1 => "[#{first_page}]", 2 => "[#{contributor_json("last", 1)}]"}
    with_api_server(pages) do |base, seen|
      options = options_from("contributors:\n  max: 500")
      users = HallOfFame::GitHubApi.new(options: options, api_base: base).contributors("o/r")
      users.size.should eq(101)
      seen.size.should eq(2)
    end
  end

  it "stops at max" do
    first_page = (1..100).map { |index| contributor_json("user#{index}", 1) }.join(",")
    pages = {1 => "[#{first_page}]", 2 => "[#{contributor_json("ignored", 1)}]"}
    with_api_server(pages) do |base, seen|
      options = options_from("contributors:\n  max: 10")
      users = HallOfFame::GitHubApi.new(options: options, api_base: base).contributors("o/r")
      users.size.should eq(10)
      seen.size.should eq(1)
    end
  end

  it "maps anonymous contributors to identicons when enabled" do
    pages = {1 => "[#{ANON_JSON}]"}
    with_api_server(pages) do |base, seen|
      HallOfFame::GitHubApi.new(api_base: base).contributors("o/r").should be_empty

      options = options_from("contributors:\n  include_anonymous: true")
      users = HallOfFame::GitHubApi.new(options: options, api_base: base).contributors("o/r")
      users.size.should eq(1)
      users[0].login.should eq("Ghost Writer")
      users[0].avatar_url.should eq("https://github.com/identicons/Ghost%20Writer.png")
      users[0].link.should eq("https://github.com/o/r/commits?author=ghost%40example.com")
      users[0].weight.should eq(7)
      seen.last[0].should contain("anon=1")
    end
  end

  it "sends the token as a bearer authorization" do
    pages = {1 => "[]"}
    with_api_server(pages) do |base, seen|
      HallOfFame::GitHubApi.new(token: "sekrit", api_base: base).contributors("o/r")
      seen.last[1].should eq("Bearer sekrit")

      HallOfFame::GitHubApi.new(api_base: base).contributors("o/r")
      seen.last[1].should be_nil
    end
  end

  it "raises a friendly error for missing repositories" do
    with_api_server({} of Int32 => String, status: 404) do |base, _seen|
      expect_raises(HallOfFame::ApiError, /not found or not accessible/) do
        HallOfFame::GitHubApi.new(api_base: base).contributors("o/r")
      end
    end
  end

  it "explains rate limiting with the reset time" do
    headers = HTTP::Headers{"x-ratelimit-remaining" => "0", "x-ratelimit-reset" => "1753400000"}
    with_api_server({} of Int32 => String, status: 403, headers: headers) do |base, _seen|
      error = expect_raises(HallOfFame::ApiError, /rate limit exceeded/) do
        HallOfFame::GitHubApi.new(api_base: base).contributors("o/r")
      end
      message = error.message || ""
      message.should match(/resets at 20\d\d-/)
      message.should contain("pass a `token`")
    end
  end

  it "rejects malformed repo values" do
    expect_raises(HallOfFame::ApiError, /owner\/name/) do
      HallOfFame::GitHubApi.new.contributors("not-a-repo")
    end
  end
end
