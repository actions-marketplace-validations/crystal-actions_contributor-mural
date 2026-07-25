require "yaml"

module HallOfFame
  class ConfigError < Exception
    getter line : Int32?

    def initialize(message : String, @line : Int32? = nil)
      super(message)
    end
  end

  enum Source
    List
    Contributors
    Both

    def uses_list? : Bool
      list? || both?
    end

    def uses_contributors? : Bool
      contributors? || both?
    end
  end

  enum Style
    Grid
    Honeycomb
    Mosaic
  end

  enum Shape
    Circle
    Rounded
    Square
  end

  enum SortMode
    Weight
    Login
    None
  end

  class Config
    include YAML::Serializable
    include YAML::Serializable::Strict

    property source : Source = Source::List
    property style : Style = Style::Grid
    property output : String = "HALL_OF_FAME.svg"
    property outputs : Array(OutputEntry)? = nil
    property users : Array(UserEntry) = [] of UserEntry
    property groups : Array(String)? = nil
    property contributors : ContributorsConfig = ContributorsConfig.new
    property exclude : Array(String) = [] of String
    property sort : SortMode = SortMode::Weight
    property limit : Int32? = nil
    property? fail_on_missing : Bool = false
    property grid : GridConfig = GridConfig.new
    property honeycomb : HoneycombConfig = HoneycombConfig.new
    property mosaic : MosaicConfig = MosaicConfig.new
    property theme : ThemeConfig = ThemeConfig.new

    def self.load(path : String) : Config
      raise ConfigError.new("config file not found: #{path}") unless File.exists?(path)
      begin
        config = from_yaml(File.read(path))
      rescue ex : YAML::ParseException
        raise ConfigError.new("invalid config: #{ex.message}", ex.line_number)
      end
      config.validate!
      config
    end

    # The (path, style) pairs to render: the `outputs` array when present,
    # otherwise the single `output`/`style` pair.
    def render_targets : Array({String, Style})
      if entries = outputs
        entries.map { |entry| {entry.path, entry.style || style} }
      else
        [{output, style}]
      end
    end

    def validate! : Nil
      errors = [] of String

      if source.list? && users.empty?
        errors << "source 'list' requires a non-empty `users` list"
      end

      validate_users(errors)
      validate_outputs(errors)
      validate_groups(errors)

      if lim = limit
        errors << "`limit` must be >= 1" if lim < 1
      end
      errors << "contributors `max` must be >= 1" if contributors.max < 1

      errors.concat(grid.validate)
      errors.concat(honeycomb.validate)
      errors.concat(mosaic.validate)

      raise ConfigError.new(errors.join("; ")) unless errors.empty?
    end

    private def validate_users(errors : Array(String)) : Nil
      seen = Set(String).new
      users.each do |user|
        errors << "user entry with empty `login`" if user.login.strip.empty?
        errors << "duplicate user login: #{user.login}" unless seen.add?(user.login.downcase)
        if weight = user.weight
          errors << "user #{user.login}: `weight` must be >= 1" if weight < 1
        end
      end
    end

    private def validate_groups(errors : Array(String)) : Nil
      if explicit = groups
        errors << "`groups` entries must not be empty" if explicit.any?(&.strip.empty?)
        errors << "duplicate `groups` entries" if explicit.uniq.size != explicit.size

        known = explicit.to_set
        users.each do |user|
          if group = user.group
            errors << "user #{user.login}: group #{group.inspect} is not listed in `groups`" unless known.includes?(group)
          end
        end
        if group = contributors.group
          errors << "contributors: group #{group.inspect} is not listed in `groups`" unless known.includes?(group)
        end
      end
    end

    private def validate_outputs(errors : Array(String)) : Nil
      render_targets.each do |path, _|
        if path.strip.empty?
          errors << "output path must not be empty"
        elsif !path.ends_with?(".svg")
          errors << "output path must end with .svg: #{path}"
        end
        if path.starts_with?('/') || Path[path].parts.includes?("..")
          errors << "output path must be relative to the repository: #{path}"
        end
      end
      paths = render_targets.map(&.first)
      errors << "duplicate output paths" if paths.uniq.size != paths.size
    end
  end

  class OutputEntry
    include YAML::Serializable
    include YAML::Serializable::Strict

    property path : String
    property style : Style? = nil
  end

  class UserEntry
    include YAML::Serializable
    include YAML::Serializable::Strict

    property login : String
    property name : String? = nil
    property link : String? = nil
    property avatar_url : String? = nil
    property weight : Int32? = nil
    property role : String? = nil
    property group : String? = nil
  end

  class ContributorsConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    property repo : String? = nil
    property? include_bots : Bool = false
    property? include_anonymous : Bool = false
    property max : Int32 = 100
    property group : String? = nil

    def initialize
    end
  end

  class GridConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    property columns : Int32 = 8
    property avatar_size : Int32 = 64
    property shape : Shape = Shape::Circle
    property margin : Int32 = 8
    property? show_names : Bool = true
    property truncate : Int32 = 12

    def initialize
    end

    def validate : Array(String)
      errors = [] of String
      errors << "grid `columns` must be >= 1" if columns < 1
      errors << "grid `avatar_size` must be >= 8" if avatar_size < 8
      errors << "grid `margin` must be >= 0" if margin < 0
      errors << "grid `truncate` must be >= 0" if truncate < 0
      errors
    end
  end

  class HoneycombConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    property columns : Int32 = 9
    property cell_size : Int32 = 72
    property gap : Int32 = 4

    def initialize
    end

    def validate : Array(String)
      errors = [] of String
      errors << "honeycomb `columns` must be >= 1" if columns < 1
      errors << "honeycomb `cell_size` must be >= 8" if cell_size < 8
      errors << "honeycomb `gap` must be >= 0" if gap < 0
      errors
    end
  end

  class MosaicConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    property width : Int32 = 800
    property base_cell : Int32 = 48
    property tiers : Array(Int32) = [3, 2, 1]
    property gap : Int32 = 2

    def initialize
    end

    def validate : Array(String)
      errors = [] of String
      errors << "mosaic `base_cell` must be >= 8" if base_cell < 8
      errors << "mosaic `width` must be >= `base_cell`" if width < base_cell
      errors << "mosaic `gap` must be >= 0" if gap < 0
      if tiers.empty?
        errors << "mosaic `tiers` must not be empty"
      elsif tiers.any? { |tier| tier < 1 }
        errors << "mosaic `tiers` values must be >= 1"
      end
      errors
    end
  end

  class ThemeConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    property background : String = "transparent"
    property label_color : String = "#57606a"
    property role_color : String = "#6e7781"
    property title_color : String = "#24292f"
    property font_family : String = "-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

    def initialize
    end
  end
end
