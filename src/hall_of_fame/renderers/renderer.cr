module HallOfFame
  # Turns embedded users into an SVG document. Styles implement `defs` (shared
  # clip paths, emitted once), `block_size`, and `draw_block` (one section of
  # users at a vertical offset); the base class stacks sections with optional
  # group titles. PNG output slots in later as another subclass without
  # touching the pipeline.
  abstract class Renderer
    TITLE_HEIGHT = 30.0
    SECTION_GAP  = 12.0

    def initialize(@config : Config)
    end

    # Pixel size at which to fetch this user's avatar (2x render size for
    # crisp display on high-DPI screens).
    abstract def fetch_size(user : ResolvedUser) : Int32

    # Called with the full user list before avatars are fetched, so renderers
    # with relative sizing (mosaic tiers) can precompute per-user sizes.
    def prepare(users : Array(ResolvedUser)) : Nil
    end

    def render(groups : Array({String?, Array(EmbeddedUser)})) : String
      groups = groups.reject { |(_title, users)| users.empty? }
      return SVG.document(16, 16, theme.background) { } if groups.empty?

      sized = groups.map { |(title, users)| {title, users, block_size(users)} }
      width = sized.max_of { |(_title, _users, size)| size[0] }
      height = 0.0
      sized.each_with_index do |(title, _users, size), index|
        height += SECTION_GAP if index.positive?
        height += TITLE_HEIGHT if title
        height += size[1]
      end

      SVG.document(width, height, theme.background) do |io|
        defs(io)
        y = 0.0
        sized.each_with_index do |(title, users, size), index|
          y += SECTION_GAP if index.positive?
          if title
            io << %(  <text x="#{SVG.num(title_inset)}" y="#{SVG.num(y + 19)}" text-anchor="start" font-family="#{SVG.escape(theme.font_family)}" font-size="14" font-weight="600" fill="#{SVG.escape(theme.title_color)}">#{SVG.escape(title)}</text>\n)
            y += TITLE_HEIGHT
          end
          draw_block(io, users, y)
          y += size[1]
        end
      end
    end

    # Single-section convenience (specs, simple callers).
    def render(users : Array(EmbeddedUser)) : String
      render([{nil.as(String?), users}])
    end

    def self.for(style : Style, config : Config) : Renderer
      case style
      in .grid?      then Renderers::Grid.new(config)
      in .honeycomb? then Renderers::Honeycomb.new(config)
      in .mosaic?    then Renderers::Mosaic.new(config)
      end
    end

    # Style-wide <defs>, emitted once per document.
    protected def defs(io : String::Builder) : Nil
    end

    # Content size of one section: {width, height}.
    protected abstract def block_size(users : Array(EmbeddedUser)) : {Float64, Float64}

    # Emit one section's content, shifted down by `y_offset`.
    protected abstract def draw_block(io : String::Builder, users : Array(EmbeddedUser), y_offset : Float64) : Nil

    # Left inset aligning section titles with block content.
    protected def title_inset : Float64
      8.0
    end

    protected def theme : ThemeConfig
      @config.theme
    end

    protected def truncate(name : String, limit : Int32) : String
      return name if limit == 0 || name.size <= limit
      "#{name[0, limit - 1]}…"
    end

    protected def title_for(user : EmbeddedUser) : String
      base = user.name == user.login ? user.login : "#{user.name} (@#{user.login})"
      if role = user.role
        "#{base} · #{role}"
      else
        base
      end
    end

    protected def label(io : String::Builder, text : String, x : Int32 | Float64, y : Int32 | Float64) : Nil
      io << %(    <text x="#{SVG.num(x)}" y="#{SVG.num(y)}" text-anchor="middle" font-family="#{SVG.escape(theme.font_family)}" font-size="11" fill="#{SVG.escape(theme.label_color)}">#{SVG.escape(text)}</text>\n)
    end
  end
end
