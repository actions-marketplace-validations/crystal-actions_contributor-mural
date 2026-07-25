require "http/client"
require "json"
require "uri"

module HallOfFame
  class ApiError < Exception
  end

  # Seam for contributor retrieval so specs can inject a fake.
  abstract class ContributorSource
    abstract def contributors(repo : String) : Array(ResolvedUser)
  end

  # Fetches repository contributors from the GitHub REST API.
  # Contribution counts become user weights.
  class GitHubApi < ContributorSource
    PER_PAGE     = 100
    MAX_ATTEMPTS =   3

    def initialize(@token : String? = nil,
                   @options : ContributorsConfig = ContributorsConfig.new,
                   @api_base : String = "https://api.github.com",
                   @backoff_base : Time::Span = 1.second)
    end

    def contributors(repo : String) : Array(ResolvedUser)
      unless repo.matches?(%r{\A[^/\s]+/[^/\s]+\z})
        raise ApiError.new("contributors `repo` must look like owner/name, got: #{repo.inspect}")
      end

      users = [] of ResolvedUser
      page = 1
      loop do
        batch = fetch_page(repo, page)
        batch.each do |dto|
          next unless user = to_user(dto, repo)
          users << user
          return users if users.size >= @options.max
        end
        break if batch.size < PER_PAGE
        page += 1
      end
      users
    end

    private struct ContributorDTO
      include JSON::Serializable

      getter login : String? = nil
      getter avatar_url : String? = nil
      getter html_url : String? = nil
      getter contributions : Int32 = 0
      getter type : String = "User"
      getter name : String? = nil
      getter email : String? = nil
    end

    private def fetch_page(repo : String, page : Int32) : Array(ContributorDTO)
      params = URI::Params.build do |form|
        form.add "per_page", PER_PAGE.to_s
        form.add "page", page.to_s
        form.add "anon", "1" if @options.include_anonymous?
      end
      url = "#{@api_base}/repos/#{repo}/contributors?#{params}"

      attempt = 0
      loop do
        attempt += 1
        begin
          return handle_response(HTTP::Client.get(url, headers: headers), repo)
        rescue ex : ApiError
          raise ex
        rescue ex : IO::Error
          raise ApiError.new("network error talking to GitHub: #{ex.message}") if attempt >= MAX_ATTEMPTS
        end
        sleep @backoff_base * (2 ** (attempt - 1))
      end
    end

    private def handle_response(response : HTTP::Client::Response, repo : String) : Array(ContributorDTO)
      case response.status_code
      when 200
        Array(ContributorDTO).from_json(response.body)
      when 204
        [] of ContributorDTO
      when 401
        raise ApiError.new("GitHub API rejected the token (401) — check the `token` input")
      when 403, 429
        raise rate_limit_error(response)
      when 404
        raise ApiError.new("repository not found or not accessible: #{repo} (pass a token with repo access?)")
      else
        raise ApiError.new("GitHub API returned #{response.status_code} for #{repo}")
      end
    end

    private def rate_limit_error(response : HTTP::Client::Response) : ApiError
      if response.headers["x-ratelimit-remaining"]? == "0"
        reset = response.headers["x-ratelimit-reset"]?.try(&.to_i64?)
        at = reset ? " (resets at #{Time.unix(reset).to_rfc3339})" : ""
        ApiError.new("GitHub API rate limit exceeded#{at} — pass a `token` to raise the limit")
      else
        ApiError.new("GitHub API denied the request (#{response.status_code})")
      end
    end

    private def to_user(dto : ContributorDTO, repo : String) : ResolvedUser?
      if login = dto.login
        return if bot?(dto) && !@options.include_bots?
        ResolvedUser.new(
          login: login,
          link: dto.html_url || "https://github.com/#{login}",
          avatar_url: dto.avatar_url,
          weight: Math.max(dto.contributions, 1),
          group: @options.group,
        )
      else
        return unless @options.include_anonymous?
        seed = dto.name || dto.email || "anonymous"
        ResolvedUser.new(
          login: seed,
          link: "https://github.com/#{repo}/commits?author=#{URI.encode_www_form(dto.email || seed)}",
          avatar_url: "https://github.com/identicons/#{URI.encode_path_segment(seed)}.png",
          weight: Math.max(dto.contributions, 1),
          group: @options.group,
        )
      end
    end

    private def bot?(dto : ContributorDTO) : Bool
      dto.type == "Bot" || !!dto.login.try(&.ends_with?("[bot]"))
    end

    private def headers : HTTP::Headers
      result = HTTP::Headers{
        "Accept"               => "application/vnd.github+json",
        "User-Agent"           => "hall-of-fame/#{VERSION}",
        "X-GitHub-Api-Version" => "2022-11-28",
      }
      if token = @token
        result["Authorization"] = "Bearer #{token}" unless token.empty?
      end
      result
    end
  end
end
