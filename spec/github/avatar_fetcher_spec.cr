require "../spec_helper"
require "http/server"

# Boots a throwaway local HTTP server for redirect/error behavior. No external
# network is touched.
private def with_test_server(&)
  requests = [] of String
  server = HTTP::Server.new do |context|
    path = context.request.path
    requests << path
    case path
    when "/ok.png"
      context.response.content_type = "image/jpeg"
      context.response.print "JPEGDATA"
    when "/redirect"
      context.response.status_code = 301
      context.response.headers["Location"] = "/ok.png"
    when "/relative-redirect"
      context.response.status_code = 302
      context.response.headers["Location"] = "ok.png"
    when "/loop"
      context.response.status_code = 302
      context.response.headers["Location"] = "/loop"
    when "/missing"
      context.response.status_code = 404
    when "/flaky"
      if requests.count("/flaky") < 3
        context.response.status_code = 500
      else
        context.response.content_type = "image/png"
        context.response.print "RECOVERED"
      end
    else
      context.response.status_code = 500
    end
  end
  address = server.bind_unused_port "127.0.0.1"
  spawn { server.listen }
  begin
    yield "http://#{address}", requests
  ensure
    server.close
  end
end

private def user_with(avatar_url : String) : HallOfFame::ResolvedUser
  HallOfFame::ResolvedUser.new("tester", avatar_url: avatar_url)
end

describe HallOfFame::HTTPAvatarSource do
  describe "#url_for" do
    it "appends the size to explicit avatar URLs" do
      source = HallOfFame::HTTPAvatarSource.new
      source.url_for(user_with("https://example.com/a.png"), 128)
        .should eq("https://example.com/a.png?s=128")
      source.url_for(user_with("https://example.com/a.png?v=4"), 128)
        .should eq("https://example.com/a.png?v=4&s=128")
    end

    it "derives the GitHub avatar URL from the login" do
      source = HallOfFame::HTTPAvatarSource.new
      user = HallOfFame::ResolvedUser.new("hahwul")
      source.url_for(user, 128).should eq("https://github.com/hahwul.png?size=128")
    end
  end

  describe "#fetch" do
    it "returns bytes and content type" do
      with_test_server do |base, _requests|
        source = HallOfFame::HTTPAvatarSource.new(backoff_base: 0.seconds)
        bytes, content_type = source.fetch(user_with("#{base}/ok.png"), 64)
        String.new(bytes).should eq("JPEGDATA")
        content_type.should eq("image/jpeg")
      end
    end

    it "follows absolute and relative redirects" do
      with_test_server do |base, _requests|
        source = HallOfFame::HTTPAvatarSource.new(backoff_base: 0.seconds)
        bytes, _ = source.fetch(user_with("#{base}/redirect"), 64)
        String.new(bytes).should eq("JPEGDATA")

        bytes, _ = source.fetch(user_with("#{base}/relative-redirect"), 64)
        String.new(bytes).should eq("JPEGDATA")
      end
    end

    it "gives up on redirect loops" do
      with_test_server do |base, _requests|
        source = HallOfFame::HTTPAvatarSource.new(backoff_base: 0.seconds)
        expect_raises(HallOfFame::AvatarError, /too many redirects/) do
          source.fetch(user_with("#{base}/loop"), 64)
        end
      end
    end

    it "does not retry a 404" do
      with_test_server do |base, requests|
        source = HallOfFame::HTTPAvatarSource.new(backoff_base: 0.seconds)
        error = expect_raises(HallOfFame::AvatarError, /404/) do
          source.fetch(user_with("#{base}/missing"), 64)
        end
        error.status.should eq(404)
        requests.count("/missing").should eq(1)
      end
    end

    it "retries server errors and succeeds" do
      with_test_server do |base, requests|
        source = HallOfFame::HTTPAvatarSource.new(backoff_base: 0.seconds)
        bytes, _ = source.fetch(user_with("#{base}/flaky"), 64)
        String.new(bytes).should eq("RECOVERED")
        requests.count("/flaky").should eq(3)
      end
    end
  end
end
