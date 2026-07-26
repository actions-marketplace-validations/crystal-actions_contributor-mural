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
    property members : MembersConfig? = nil
    property stargazers : StargazersConfig? = nil
    property sponsors : SponsorsConfig? = nil
    property exclude : Array(String) = [] of String
    property sort : SortMode = SortMode::Weight
    property limit : Int32? = nil
    property? fail_on_missing : Bool = false
    property grid : GridConfig = GridConfig.new
    property honeycomb : HoneycombConfig = HoneycombConfig.new
    property mosaic : MosaicConfig = MosaicConfig.new
    property theme : ThemeConfig = ThemeConfig.new
    property png : PngConfig = PngConfig.new

    def self.empty : Config
      from_yaml("{}")
    end

    # True when any configured source needs the GitHub API.
    def api_sources? : Bool
      source.uses_contributors? || !members.nil? || !stargazers.nil? || !sponsors.nil?
    end

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

    # The (path, style, mode override) tuples to render: the `outputs` array
    # when present, otherwise the single `output`/`style` pair.
    def render_targets : Array({String, Style, ThemeMode?})
      if entries = outputs
        entries.map { |entry| {entry.path, entry.style || style, entry.mode} }
      else
        [{output, style, nil.as(ThemeMode?)}]
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
      validate_api_sources(errors)

      errors.concat(grid.validate)
      errors.concat(honeycomb.validate)
      errors.concat(mosaic.validate)
      errors.concat(theme.validate)

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
        if (avatar = user.avatar_url) && !avatar.matches?(%r{\Ahttps?://}i)
          if avatar.starts_with?('/') || Path[avatar].parts.includes?("..")
            errors << "user #{user.login}: local `avatar_url` must be relative to the repository: #{avatar}"
          end
        end
      end
    end

    private def validate_api_sources(errors : Array(String)) : Nil
      errors << "contributors `max` must be >= 1" if contributors.max < 1
      if block = members
        errors << "members `org` must not be empty" if block.org.strip.empty?
        errors << "members `max` must be >= 1" if block.max < 1
      end
      if block = stargazers
        errors << "stargazers `max` must be >= 1" if block.max < 1
      end
      if block = sponsors
        errors << "sponsors `max` must be >= 1" if block.max < 1
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
        {
          "contributors" => contributors.group,
          "members"      => members.try(&.group),
          "stargazers"   => stargazers.try(&.group),
          "sponsors"     => sponsors.try(&.group),
        }.each do |section, group|
          next unless group
          errors << "#{section}: group #{group.inspect} is not listed in `groups`" unless known.includes?(group)
        end
      end
    end

    private def validate_outputs(errors : Array(String)) : Nil
      render_targets.each do |path, _style, _mode|
        if path.strip.empty?
          errors << "output path must not be empty"
        elsif !path.ends_with?(".svg") && !path.ends_with?(".png")
          errors << "output path must end with .svg or .png: #{path}"
        end
        if path.starts_with?('/') || Path[path].parts.includes?("..")
          errors << "output path must be relative to the repository: #{path}"
        end
      end
      paths = render_targets.map(&.first)
      errors << "duplicate output paths" if paths.uniq.size != paths.size
      errors << "png `scale` must be positive" if png.scale <= 0
    end
  end

  class OutputEntry
    include YAML::Serializable
    include YAML::Serializable::Strict

    property path : String
    property style : Style? = nil
    # Per-output theme mode override, e.g. a light/dark PNG or SVG pair.
    property mode : ThemeMode? = nil
  end

  class PngConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    property scale : Float64 = 2.0

    def initialize
    end
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

  # Presence of the block enables the source.
  class MembersConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    property org : String
    property max : Int32 = 100
    property group : String? = nil
  end

  class StargazersConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    property repo : String? = nil
    property max : Int32 = 100
    property group : String? = nil
  end

  class SponsorsConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    property login : String? = nil
    property max : Int32 = 100
    property group : String? = nil
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

  enum ThemeMode
    Auto
    Light
    Dark
  end

  record Palette,
    background : String,
    label_color : String,
    role_color : String,
    title_color : String

  class PaletteOverride
    include YAML::Serializable
    include YAML::Serializable::Strict

    property background : String? = nil
    property label_color : String? = nil
    property role_color : String? = nil
    property title_color : String? = nil

    def initialize
    end
  end

  class ThemeConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    # {light, dark} palette pairs.
    PRESETS = {
      "github" => {
        Palette.new("transparent", "#57606a", "#6e7781", "#24292f"),
        Palette.new("transparent", "#8b949e", "#7d8590", "#e6edf3"),
      },
      "midnight" => {
        Palette.new("#0b1021", "#8f9bb3", "#5c6784", "#dfe6f3"),
        Palette.new("#0b1021", "#8f9bb3", "#5c6784", "#dfe6f3"),
      },
      "paper" => {
        Palette.new("#faf8f2", "#6f6857", "#a39a86", "#3d3629"),
        Palette.new("#221f1a", "#a89f8d", "#7d7666", "#ece5d8"),
      },
      "mono" => {
        Palette.new("#ffffff", "#444444", "#888888", "#000000"),
        Palette.new("#000000", "#bbbbbb", "#777777", "#ffffff"),
      },
    }

    # Colors land in a <style> block, so restrict them to a safe subset.
    SAFE_COLOR = /\A[#a-zA-Z0-9(),.%\- ]+\z/

    property preset : String = "github"
    property mode : ThemeMode = ThemeMode::Auto
    property background : String? = nil
    property label_color : String? = nil
    property role_color : String? = nil
    property title_color : String? = nil
    property dark : PaletteOverride = PaletteOverride.new
    property font_family : String = "-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

    def initialize
    end

    def light_palette : Palette
      base = PRESETS[preset]?.try(&.first) || PRESETS["github"].first
      Palette.new(
        background: background || base.background,
        label_color: label_color || base.label_color,
        role_color: role_color || base.role_color,
        title_color: title_color || base.title_color,
      )
    end

    def dark_palette : Palette
      base = PRESETS[preset]?.try(&.last) || PRESETS["github"].last
      Palette.new(
        background: dark.background || base.background,
        label_color: dark.label_color || base.label_color,
        role_color: dark.role_color || base.role_color,
        title_color: dark.title_color || base.title_color,
      )
    end

    def validate : Array(String)
      errors = [] of String
      unless PRESETS.has_key?(preset)
        errors << "unknown theme `preset`: #{preset} (known: #{PRESETS.keys.join(", ")})"
      end
      {light_palette, dark_palette}.each do |palette|
        {palette.background, palette.label_color, palette.role_color, palette.title_color}.each do |color|
          errors << "theme color contains unsafe characters: #{color.inspect}" unless color.matches?(SAFE_COLOR)
        end
      end
      errors.uniq
    end
  end
end
