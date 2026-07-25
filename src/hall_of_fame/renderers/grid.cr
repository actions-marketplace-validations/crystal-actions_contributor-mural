module HallOfFame::Renderers
  # Classic avatar wall: fixed-size avatars in rows, optional name labels.
  class Grid < Renderer
    LABEL_HEIGHT = 18
    CLIP_ID      = "avatar-clip"

    def fetch_size(user : ResolvedUser) : Int32
      @config.grid.avatar_size * 2
    end

    def render(users : Array(EmbeddedUser)) : String
      grid = @config.grid
      cols = users.empty? ? 1 : Math.min(grid.columns, users.size)
      rows = (users.size + cols - 1) // cols
      label_height = grid.show_names? ? LABEL_HEIGHT : 0
      cell_w = grid.avatar_size
      cell_h = grid.avatar_size + label_height
      width = cols * cell_w + (cols + 1) * grid.margin
      height = rows.zero? ? grid.margin * 2 : rows * cell_h + (rows + 1) * grid.margin

      SVG.document(width, height, theme.background) do |io|
        clip_id = emit_clip(io, grid.shape)
        users.each_with_index do |user, index|
          row, col = index.divmod(cols)
          x = grid.margin + col * (cell_w + grid.margin)
          y = grid.margin + row * (cell_h + grid.margin)

          io << %(  <a href="#{SVG.escape(user.link)}" target="_blank">\n)
          io << %(    <title>#{SVG.escape(title_for(user))}</title>\n)
          io << %(    <image href="#{user.data_uri}" x="#{x}" y="#{y}" width="#{grid.avatar_size}" height="#{grid.avatar_size}" preserveAspectRatio="xMidYMid slice")
          io << %( clip-path="url(##{clip_id})") if clip_id
          io << "/>\n"
          if grid.show_names?
            label(io, truncate(user.name, grid.truncate), x + cell_w / 2, y + grid.avatar_size + 13)
          end
          io << "  </a>\n"
        end
      end
    end

    private def emit_clip(io : String::Builder, shape : Shape) : String?
      inner =
        case shape
        in .square?  then return
        in .circle?  then %(<circle cx="0.5" cy="0.5" r="0.5"/>)
        in .rounded? then %(<rect width="1" height="1" rx="0.15"/>)
        end
      io << %(  <defs><clipPath id="#{CLIP_ID}" clipPathUnits="objectBoundingBox">#{inner}</clipPath></defs>\n)
      CLIP_ID
    end
  end
end
