module HallOfFame
  class CommitError < Exception
  end

  # Commits and pushes generated files with git. Identity is passed per
  # command (-c) so the user's git config is never mutated; the global
  # safe.directory entry is only added inside the actions runner, where the
  # workspace is owned by a different uid than the container user.
  class Committer
    BOT_NAME  = "github-actions[bot]"
    BOT_EMAIL = "41898282+github-actions[bot]@users.noreply.github.com"

    def initialize(@workspace : String, @message : String)
    end

    # Returns true when a commit was pushed, false when nothing changed.
    def commit(paths : Array(String)) : Bool
      if ENV["GITHUB_ACTIONS"]? == "true"
        run(["config", "--global", "--add", "safe.directory", @workspace], repo: false)
      end
      run(["add", "--"] + paths)
      return false unless staged_changes?
      run(["-c", "user.name=#{BOT_NAME}", "-c", "user.email=#{BOT_EMAIL}",
           "commit", "-m", @message])
      run(["push"])
      true
    end

    private def staged_changes? : Bool
      status = Process.run("git", ["-C", @workspace, "diff", "--cached", "--quiet"])
      !status.success?
    end

    private def run(command : Array(String), repo : Bool = true) : Nil
      argv = repo ? ["-C", @workspace] : [] of String
      argv += command
      output = IO::Memory.new
      status = Process.run("git", argv, output: output, error: output)
      return if status.success?
      raise CommitError.new("`git #{command.join(' ')}` failed: #{output.to_s.strip}")
    end
  end
end
