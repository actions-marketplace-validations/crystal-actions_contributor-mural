module HallOfFame
  # Turns embedded users into an SVG document. PNG output slots in later as
  # another subclass without touching the pipeline.
  abstract class Renderer
    def initialize(@config : Config)
    end

    abstract def render(users : Array(EmbeddedUser)) : String

    # Pixel size at which to fetch this user's avatar (2x render size for
    # crisp display on high-DPI screens).
    abstract def fetch_size(user : ResolvedUser) : Int32

    # Called with the full user list before avatars are fetched, so renderers
    # with relative sizing (mosaic tiers) can precompute per-user sizes.
    def prepare(users : Array(ResolvedUser)) : Nil
    end

    def self.for(style : Style, config : Config) : Renderer
      case style
      in .grid?      then Renderers::Grid.new(config)
      in .honeycomb? then Renderers::Honeycomb.new(config)
      in .mosaic?    then Renderers::Mosaic.new(config)
      end
    end

    protected def theme : ThemeConfig
      @config.theme
    end

    protected def truncate(name : String, limit : Int32) : String
      return name if limit == 0 || name.size <= limit
      "#{name[0, limit - 1]}…"
    end

    protected def title_for(user : EmbeddedUser) : String
      user.name == user.login ? user.login : "#{user.name} (@#{user.login})"
    end

    protected def label(io : String::Builder, text : String, x : Int32 | Float64, y : Int32 | Float64) : Nil
      io << %(    <text x="#{SVG.num(x)}" y="#{SVG.num(y)}" text-anchor="middle" font-family="#{SVG.escape(theme.font_family)}" font-size="11" fill="#{SVG.escape(theme.label_color)}">#{SVG.escape(text)}</text>\n)
    end
  end
end
