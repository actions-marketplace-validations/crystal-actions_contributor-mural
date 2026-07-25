require "base64"

module HallOfFame
  # Fetches avatars in parallel and turns them into base64 data URIs.
  # Results are cached by URL so multiple render targets reuse fetches.
  class Embedder
    def initialize(@source : AvatarSource, @concurrency : Int32 = 8)
      @cache = {} of String => String | AvatarError
    end

    # Returns users with embedded avatars (input order preserved) and the
    # logins skipped due to fetch failures. Raises the first failure instead
    # when `fail_on_missing` is set.
    def embed(users : Array(ResolvedUser), renderer : Renderer,
              fail_on_missing : Bool) : {Array(EmbeddedUser), Array(String)}
      jobs = users.map { |user| {user, renderer.fetch_size(user)} }
      fetch_missing(jobs.uniq { |user, size| @source.url_for(user, size) })

      embedded = [] of EmbeddedUser
      skipped = [] of String
      jobs.each do |user, size|
        case result = @cache[@source.url_for(user, size)]
        in String
          embedded << EmbeddedUser.new(user, result)
        in AvatarError
          raise AvatarError.new("#{user.login}: #{result.message}", result.status) if fail_on_missing
          skipped << user.login
        end
      end
      {embedded, skipped}
    end

    private def fetch_missing(jobs : Array({ResolvedUser, Int32})) : Nil
      pending = jobs.reject { |user, size| @cache.has_key?(@source.url_for(user, size)) }
      return if pending.empty?

      channel = Channel({String, String | AvatarError}).new
      queue = Channel({ResolvedUser, Int32}).new(pending.size)
      pending.each { |job| queue.send(job) }
      queue.close

      Math.min(@concurrency, pending.size).times do
        spawn do
          while job = queue.receive?
            user, size = job
            url = @source.url_for(user, size)
            result = begin
              bytes, content_type = @source.fetch(user, size)
              "data:#{content_type};base64,#{Base64.strict_encode(bytes)}".as(String | AvatarError)
            rescue ex : AvatarError
              ex.as(String | AvatarError)
            end
            channel.send({url, result})
          end
        end
      end

      pending.size.times do
        url, result = channel.receive
        @cache[url] = result
      end
    end
  end
end
