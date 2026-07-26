module HallOfFame::Renderers
  # Classic avatar wall: fixed-size avatars in rows, optional name labels and
  # a smaller role line beneath them.
  class Grid < Renderer
    LABEL_HEIGHT = 18
    ROLE_HEIGHT  = 14
    CLIP_ID      = "avatar-clip"

    def fetch_size(user : ResolvedUser) : Int32
      @config.grid.avatar_size * 2
    end

    protected def title_inset : Float64
      @config.grid.margin.to_f
    end

    protected def defs(io : String::Builder) : Nil
      inner =
        case @config.grid.shape
        in .square?  then return
        in .circle?  then %(<circle cx="0.5" cy="0.5" r="0.5"/>)
        in .rounded? then %(<rect width="1" height="1" rx="0.15"/>)
        end
      io << %(  <defs><clipPath id="#{CLIP_ID}" clipPathUnits="objectBoundingBox">#{inner}</clipPath></defs>\n)
    end

    protected def block_size(users : Array(EmbeddedUser)) : {Float64, Float64}
      grid = @config.grid
      cols = Math.min(grid.columns, users.size)
      rows = (users.size + cols - 1) // cols
      cell_h = grid.avatar_size + label_height(users)
      width = cols * grid.avatar_size + (cols + 1) * grid.margin
      height = rows * cell_h + (rows + 1) * grid.margin
      {width.to_f, height.to_f}
    end

    protected def draw_block(io : String::Builder, users : Array(EmbeddedUser), y_offset : Float64) : Nil
      grid = @config.grid
      cols = Math.min(grid.columns, users.size)
      cell_w = grid.avatar_size
      cell_h = grid.avatar_size + label_height(users)
      clipped = !grid.shape.square?

      users.each_with_index do |user, index|
        row, col = index.divmod(cols)
        x = grid.margin + col * (cell_w + grid.margin)
        y = grid.margin + row * (cell_h + grid.margin) + y_offset

        io << %(  <a href="#{SVG.escape(user.link)}" target="_blank">\n)
        io << %(    <title>#{SVG.escape(title_for(user))}</title>\n)
        io << %(    <image href="#{user.data_uri}" x="#{SVG.num(x)}" y="#{SVG.num(y)}" width="#{grid.avatar_size}" height="#{grid.avatar_size}" preserveAspectRatio="xMidYMid slice")
        io << %( clip-path="url(##{CLIP_ID})") if clipped
        io << "/>\n"
        if grid.show_names?
          center = x + cell_w / 2
          label(io, truncate(user.name, grid.truncate), center, y + grid.avatar_size + 13)
          if role = user.role
            io << %(    <text x="#{SVG.num(center)}" y="#{SVG.num(y + grid.avatar_size + 26)}" text-anchor="middle" font-family="#{SVG.escape(theme.font_family)}" font-size="9" #{role_paint}>#{SVG.escape(truncate(role, grid.truncate + 4))}</text>\n)
          end
        end
        io << "  </a>\n"
      end
    end

    # Sections where at least one member has a role get a taller label area.
    private def label_height(users : Array(EmbeddedUser)) : Int32
      grid = @config.grid
      return 0 unless grid.show_names?
      LABEL_HEIGHT + (users.any?(&.role) ? ROLE_HEIGHT : 0)
    end
  end
end
