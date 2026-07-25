module HallOfFame
  # Orchestrates the pipeline: resolve users, embed avatars, render styles,
  # write files. Returns a process exit code.
  class Runner
    getter written_paths = [] of String

    def initialize(@config : Config, @avatar_source : AvatarSource,
                   @workspace : String = Dir.current,
                   @contributor_source : ContributorSource? = nil,
                   @committer : Committer? = nil)
    end

    def run : Int32
      users = Resolver.resolve(@config, fetch_contributors)
      Annotations.warning("no users to render — check `users`/`source` in the config") if users.empty?

      embedder = Embedder.new(@avatar_source)
      user_count = 0
      warned = Set(String).new

      @config.render_targets.each do |path, style|
        renderer = Renderer.for(style, @config)
        renderer.prepare(users)
        embedded, skipped = embedder.embed(users, renderer, @config.fail_on_missing?)
        skipped.each do |login|
          Annotations.warning("skipped #{login}: avatar could not be fetched") if warned.add?(login)
        end
        user_count = embedded.size

        full_path = File.join(@workspace, path)
        Dir.mkdir_p(File.dirname(full_path))
        File.write(full_path, renderer.render(Resolver.grouped(embedded, @config)))
        written_paths << path
      end

      Annotations.output("svg_path", written_paths.join(","))
      Annotations.output("user_count", user_count.to_s)

      if committer = @committer
        changed = committer.commit(written_paths)
        Annotations.output("changed", changed.to_s)
        Annotations.notice(changed ? "hall of fame updated" : "hall of fame already up to date")
      end
      0
    rescue ex : ConfigError | AvatarError | ApiError | CommitError
      Annotations.error(ex.message || ex.class.name)
      1
    end

    private def fetch_contributors : Array(ResolvedUser)
      return [] of ResolvedUser unless @config.source.uses_contributors?

      source = @contributor_source
      unless source
        raise ConfigError.new("source '#{@config.source.to_s.downcase}' needs GitHub API access, but none is configured")
      end
      repo = @config.contributors.repo || ENV["GITHUB_REPOSITORY"]?
      unless repo
        raise ConfigError.new("contributors `repo` is not set and GITHUB_REPOSITORY is not available")
      end
      source.contributors(repo)
    end
  end
end
