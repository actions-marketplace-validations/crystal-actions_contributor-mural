require "./spec_helper"

describe HallOfFame::Config do
  describe ".load" do
    it "applies defaults for a minimal config" do
      config = HallOfFame::Config.load(SpecHelper.fixture("configs", "minimal.yml"))

      config.style.should eq(HallOfFame::Style::Grid)
      config.output.should eq("HALL_OF_FAME.svg")
      config.sort.should eq(HallOfFame::SortMode::Weight)
      config.limit.should be_nil
      config.fail_on_missing?.should be_false
      config.users.size.should eq(1)
      config.users.first.login.should eq("hahwul")
      config.grid.columns.should eq(8)
      config.grid.shape.should eq(HallOfFame::Shape::Circle)
      config.honeycomb.cell_size.should eq(72)
      config.mosaic.tiers.should eq([3, 2, 1])
      config.theme.mode.should eq(HallOfFame::ThemeMode::Auto)
      config.theme.preset.should eq("github")
      config.theme.light_palette.background.should eq("transparent")
      config.theme.dark_palette.label_color.should eq("#8b949e")
      config.png.scale.should eq(2.0)
      config.render_targets.should eq([{"HALL_OF_FAME.svg", HallOfFame::Style::Grid, nil}])
    end

    it "parses every field of a full config" do
      config = HallOfFame::Config.load(SpecHelper.fixture("configs", "full.yml"))

      contributors = config.contributors.should_not be_nil
      contributors.repo.should eq("hahwul/hall-of-fame")
      contributors.include_bots?.should be_true
      contributors.max.should eq(50)
      config.exclude.should eq(["dependabot[bot]"])
      config.limit.should eq(60)
      config.fail_on_missing?.should be_true
      config.users.first.name.should eq("HAHWUL")
      config.users.first.weight.should eq(10)
      config.users[1].avatar_url.should eq("https://example.com/a.png")
      config.grid.shape.should eq(HallOfFame::Shape::Rounded)
      config.grid.show_names?.should be_false
      config.mosaic.tiers.should eq([4, 2, 1])
      config.render_targets.should eq([
        {"docs/grid.svg", HallOfFame::Style::Grid, nil},
        {"docs/hex.svg", HallOfFame::Style::Honeycomb, nil},
        {"docs/wall.png", HallOfFame::Style::Mosaic, HallOfFame::ThemeMode::Dark},
      ])
    end

    it "fails when the file does not exist" do
      expect_raises(HallOfFame::ConfigError, /not found/) do
        HallOfFame::Config.load(SpecHelper.fixture("configs", "nope.yml"))
      end
    end

    it "fails on unknown keys (typo protection)" do
      expect_raises(HallOfFame::ConfigError, /avatarsize/) do
        HallOfFame::Config.load(SpecHelper.fixture("configs", "invalid_unknown_key.yml"))
      end
    end

    it "fails when no source would produce any user" do
      expect_raises(HallOfFame::ConfigError, /nothing to render/) do
        HallOfFame::Config.load(SpecHelper.fixture("configs", "invalid_no_users.yml"))
      end
    end

    it "accepts an API-only source without a users list" do
      config = HallOfFame::Config.parse("stargazers:\n  repo: o/r")
      config.validate!
      config.api_sources?.should be_true
    end

    it "enables a source block written with no options under it" do
      config = HallOfFame::Config.parse("contributors:")
      config.validate!
      config.contributors.should_not be_nil
      config.api_sources?.should be_true
    end

    it "combines a users list with a contributors block" do
      config = HallOfFame::Config.parse(<<-YAML)
        users:
          - login: hahwul
        contributors:
          repo: o/r
        YAML

      config.validate!
      config.users.size.should eq(1)
      config.contributors.try(&.repo).should eq("o/r")
    end

    it "points at the replacement when the removed `source` key is used" do
      expect_raises(HallOfFame::ConfigError, /`source` was removed/) do
        HallOfFame::Config.parse("source: contributors")
      end
    end

    it "asks for an org when `members` is written bare" do
      expect_raises(HallOfFame::ConfigError, /`members` needs an `org`/) do
        HallOfFame::Config.parse("members:")
      end
    end

    it "names the accepted values for a misspelled enum" do
      error = expect_raises(HallOfFame::ConfigError) do
        HallOfFame::Config.load(SpecHelper.fixture("configs", "invalid_style.yml"))
      end
      message = error.message || ""
      message.should contain(%(unknown value "cubism"))
      message.should contain("grid, honeycomb, mosaic")
      message.should_not contain("HallOfFame::Style")
    end

    it "fails on an unknown style" do
      expect_raises(HallOfFame::ConfigError, /cubism/) do
        HallOfFame::Config.load(SpecHelper.fixture("configs", "invalid_style.yml"))
      end
    end

    it "fails on duplicate logins regardless of case" do
      expect_raises(HallOfFame::ConfigError, /duplicate user login/) do
        HallOfFame::Config.load(SpecHelper.fixture("configs", "invalid_dup_users.yml"))
      end
    end

    it "fails on output paths escaping the repository" do
      expect_raises(HallOfFame::ConfigError, /relative to the repository/) do
        HallOfFame::Config.load(SpecHelper.fixture("configs", "invalid_output.yml"))
      end
    end
  end

  describe "#validate!" do
    it "collects multiple errors into one message" do
      config = HallOfFame::Config.parse(<<-YAML)
        users:
          - login: hahwul
            weight: 0
        limit: 0
        grid:
          columns: 0
        YAML

      error = expect_raises(HallOfFame::ConfigError) { config.validate! }
      message = error.message || ""
      message.should contain("`weight` must be >= 1")
      message.should contain("`limit` must be >= 1")
      message.should contain("grid `columns` must be between 1 and 100")
    end

    it "parses role and group fields" do
      config = HallOfFame::Config.parse(<<-YAML)
        groups: [Contributors, Special Thanks]
        users:
          - login: hahwul
            role: Creator
            group: Contributors
          - login: octocat
            group: Special Thanks
        contributors:
          group: Contributors
        YAML

      config.validate!
      config.users[0].role.should eq("Creator")
      config.users[0].group.should eq("Contributors")
      config.users[1].role.should be_nil
      config.contributors.try(&.group).should eq("Contributors")
      config.groups.should eq(["Contributors", "Special Thanks"])
    end

    it "rejects group values missing from an explicit groups list" do
      config = HallOfFame::Config.parse(<<-YAML)
        groups: [Contributors]
        users:
          - login: hahwul
            group: Contributrs
        contributors:
          group: Nope
        YAML

      error = expect_raises(HallOfFame::ConfigError) { config.validate! }
      message = error.message || ""
      message.should contain(%(group "Contributrs" is not listed))
      message.should contain(%(contributors: group "Nope" is not listed))
    end

    it "rejects duplicate or empty groups entries" do
      config = HallOfFame::Config.parse(<<-YAML)
        groups: [A, A, " "]
        users:
          - login: hahwul
        YAML

      error = expect_raises(HallOfFame::ConfigError) { config.validate! }
      message = error.message || ""
      message.should contain("must not be empty")
      message.should contain("duplicate `groups`")
    end

    it "rejects unsupported output extensions" do
      config = HallOfFame::Config.parse(<<-YAML)
        output: art.txt
        users:
          - login: hahwul
        YAML

      expect_raises(HallOfFame::ConfigError, /end with .svg or .png/) { config.validate! }
    end
  end
end

describe "local avatar validation" do
  it "rejects local avatar paths escaping the repository" do
    config = HallOfFame::Config.parse(<<-YAML)
      users:
        - login: a
          avatar_url: ../secrets.png
        - login: b
          avatar_url: /etc/logo.png
        - login: c
          avatar_url: assets/ok.png
      YAML

    error = expect_raises(HallOfFame::ConfigError) { config.validate! }
    message = error.message || ""
    message.should contain("user a: local `avatar_url`")
    message.should contain("user b: local `avatar_url`")
    message.should_not contain("user c")
  end
end
