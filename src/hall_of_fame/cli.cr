require "option_parser"

module HallOfFame
  module CLI
    def self.run(argv = ARGV) : Int32
      config_flag = nil
      workspace_flag = nil
      commit_flag = false

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: hall-of-fame [options]"
        opts.on("-c PATH", "--config PATH", "Config file (default: #{Inputs::DEFAULT_CONFIG_PATH})") { |value| config_flag = value }
        opts.on("-w DIR", "--workspace DIR", "Directory output paths are relative to (default: cwd)") { |value| workspace_flag = value }
        opts.on("--commit", "Commit and push the generated files") { commit_flag = true }
        opts.on("-v", "--version", "Print version") do
          puts VERSION
          exit 0
        end
        opts.on("-h", "--help", "Show help") do
          puts opts
          exit 0
        end
        opts.invalid_option do |flag|
          STDERR.puts "unknown option: #{flag}"
          STDERR.puts opts
          exit 2
        end
      end
      parser.parse(argv)

      inputs = Inputs.resolve(config_flag, workspace_flag, commit_flag)

      begin
        config = Config.load(inputs.config_path)
      rescue ex : ConfigError
        Annotations.error(ex.message || "invalid config", file: inputs.config_path, line: ex.line)
        return 1
      end

      contributor_source = nil
      if config.source.uses_contributors?
        contributor_source = GitHubApi.new(inputs.token, config.contributors)
      end
      committer = inputs.commit? ? Committer.new(inputs.workspace, inputs.commit_message) : nil

      Runner.new(config, HTTPAvatarSource.new, inputs.workspace, contributor_source, committer).run
    end
  end
end
