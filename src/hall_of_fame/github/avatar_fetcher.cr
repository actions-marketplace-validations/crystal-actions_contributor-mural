require "http/client"
require "uri"

module HallOfFame
  class AvatarError < Exception
    getter status : Int32?

    def initialize(message : String, @status : Int32? = nil)
      super(message)
    end
  end

  # Seam for avatar retrieval so specs can inject a fake.
  abstract class AvatarSource
    # Stable identity of the request, used as the cache/dedupe key.
    abstract def url_for(user : ResolvedUser, size : Int32) : String

    # Returns image bytes and content type for the avatar at `size` px.
    abstract def fetch(user : ResolvedUser, size : Int32) : {Bytes, String}
  end

  # Fetches avatars over HTTP, or straight from the workspace when
  # `avatar_url` is a plain relative path (org logos, folks without a GitHub
  # account). `HTTP::Client` does not follow redirects and
  # `github.com/<login>.png` answers with a 301, so redirects are handled here.
  class HTTPAvatarSource < AvatarSource
    MAX_REDIRECTS = 5
    MAX_ATTEMPTS  = 3

    CONTENT_TYPES = {
      ".png"  => "image/png",
      ".jpg"  => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".gif"  => "image/gif",
      ".webp" => "image/webp",
      ".svg"  => "image/svg+xml",
    }

    def initialize(@workspace : String = Dir.current, @backoff_base : Time::Span = 1.second)
    end

    def self.local_path?(avatar_url : String) : Bool
      !avatar_url.matches?(%r{\Ahttps?://}i)
    end

    def url_for(user : ResolvedUser, size : Int32) : String
      if base = user.avatar_url
        return "file:#{base}" if self.class.local_path?(base)
        separator = base.includes?('?') ? '&' : '?'
        "#{base}#{separator}s=#{size}"
      else
        "https://github.com/#{URI.encode_path_segment(user.login)}.png?size=#{size}"
      end
    end

    def fetch(user : ResolvedUser, size : Int32) : {Bytes, String}
      if (base = user.avatar_url) && self.class.local_path?(base)
        read_local(base)
      else
        get_with_retries(url_for(user, size))
      end
    end

    private def read_local(path : String) : {Bytes, String}
      content_type = CONTENT_TYPES[File.extname(path).downcase]?
      unless content_type
        raise AvatarError.new("unsupported local avatar type: #{path} (use #{CONTENT_TYPES.keys.join("/")})")
      end
      full = File.join(@workspace, path)
      raise AvatarError.new("local avatar not found: #{path}", 404) unless File.file?(full)
      {File.read(full).to_slice, content_type}
    end

    private def get_with_retries(url : String) : {Bytes, String}
      attempt = 0
      loop do
        attempt += 1
        begin
          return get_following_redirects(url)
        rescue ex : AvatarError
          status = ex.status
          raise ex if status && status < 500 # client errors will not heal
          raise ex if attempt >= MAX_ATTEMPTS
        rescue ex : IO::Error
          raise AvatarError.new("network error: #{ex.message}") if attempt >= MAX_ATTEMPTS
        end
        sleep @backoff_base * (2 ** (attempt - 1)) * (1.0 + rand * 0.25)
      end
    end

    private def get_following_redirects(url : String) : {Bytes, String}
      MAX_REDIRECTS.times do
        response = HTTP::Client.get(url)
        case response.status_code
        when 200
          return {response.body.to_slice, response.content_type || "image/png"}
        when 301, 302, 303, 307, 308
          location = response.headers["Location"]?
          raise AvatarError.new("redirect without Location from #{url}") unless location
          url = URI.parse(url).resolve(location).to_s
        when 404
          raise AvatarError.new("avatar not found (404)", 404)
        else
          raise AvatarError.new("unexpected status #{response.status_code} for #{url}", response.status_code)
        end
      end
      raise AvatarError.new("too many redirects for #{url}")
    end
  end
end
