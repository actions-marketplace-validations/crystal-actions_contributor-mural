module HallOfFame
  # Orchestrates the pipeline: resolve users, embed avatars, render styles,
  # write files. Returns a process exit code.
  class Runner
    getter written_paths = [] of String

    def initialize(@config : Config, @avatar_source : AvatarSource,
                   @workspace : String = Dir.current,
                   @github_source : GitHubSource? = nil,
                   @committer : Committer? = nil,
                   @rasterizer : Rasterizer? = nil)
    end

    def run : Int32
      users = Resolver.resolve(@config, fetch_api_users)
      Annotations.warning("no users to render — check `users`/`source` in the config") if users.empty?

      embedder = Embedder.new(@avatar_source)
      user_count = 0
      warned = Set(String).new

      @config.render_targets.each do |path, style, mode_override|
        png = path.ends_with?(".png")
        mode = mode_override || @config.theme.mode
        # A PNG can't adapt to the viewer's theme, so pin auto to light.
        mode = ThemeMode::Light if png && mode.auto?

        renderer = Renderer.for(style, @config, mode)
        renderer.prepare(users)
        embedded, skipped = embedder.embed(users, renderer, @config.fail_on_missing?)
        skipped.each do |login|
          Annotations.warning("skipped #{login}: avatar could not be fetched") if warned.add?(login)
        end
        user_count = embedded.size

        svg = renderer.render(Resolver.grouped(embedded, @config))
        full_path = File.join(@workspace, path)
        Dir.mkdir_p(File.dirname(full_path))
        if png
          File.write(full_path, rasterize(svg))
        else
          File.write(full_path, svg)
        end
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
    rescue ex : ConfigError | AvatarError | ApiError | CommitError | RasterError
      Annotations.error(ex.message || ex.class.name)
      1
    end

    private def rasterize(svg : String) : Bytes
      rasterizer = @rasterizer
      raise RasterError.new("PNG output configured but no rasterizer is available") unless rasterizer
      rasterizer.rasterize(svg, @config.png.scale)
    end

    private def fetch_api_users : Array(ResolvedUser)
      return [] of ResolvedUser unless @config.api_sources?

      source = @github_source
      unless source
        raise ConfigError.new("the configured sources need GitHub API access, but none is configured")
      end

      users = [] of ResolvedUser
      if @config.source.uses_contributors?
        users.concat source.contributors(default_repo("contributors", @config.contributors.repo))
      end
      if block = @config.members
        users.concat source.members(block.org)
      end
      if block = @config.stargazers
        users.concat source.stargazers(default_repo("stargazers", block.repo))
      end
      if block = @config.sponsors
        login = block.login || ENV["GITHUB_REPOSITORY"]?.try(&.split('/').first?.presence)
        unless login
          raise ConfigError.new("sponsors `login` is not set and GITHUB_REPOSITORY is not available")
        end
        users.concat source.sponsors(login)
      end
      users
    end

    private def default_repo(section : String, configured : String?) : String
      configured || ENV["GITHUB_REPOSITORY"]? ||
        raise ConfigError.new("#{section} `repo` is not set and GITHUB_REPOSITORY is not available")
    end
  end
end
