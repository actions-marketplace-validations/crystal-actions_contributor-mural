require "./spec_helper"

describe HallOfFame::Config do
  describe ".load" do
    it "applies defaults for a minimal config" do
      config = HallOfFame::Config.load(SpecHelper.fixture("configs", "minimal.yml"))

      config.source.should eq(HallOfFame::Source::List)
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
      config.theme.background.should eq("transparent")
      config.render_targets.should eq([{"HALL_OF_FAME.svg", HallOfFame::Style::Grid}])
    end

    it "parses every field of a full config" do
      config = HallOfFame::Config.load(SpecHelper.fixture("configs", "full.yml"))

      config.source.should eq(HallOfFame::Source::Both)
      config.contributors.repo.should eq("hahwul/hall-of-fame")
      config.contributors.include_bots?.should be_true
      config.contributors.max.should eq(50)
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
        {"docs/grid.svg", HallOfFame::Style::Grid},
        {"docs/hex.svg", HallOfFame::Style::Honeycomb},
        {"docs/mosaic.svg", HallOfFame::Style::Mosaic},
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

    it "fails when source list has no users" do
      expect_raises(HallOfFame::ConfigError, /non-empty `users`/) do
        HallOfFame::Config.load(SpecHelper.fixture("configs", "invalid_no_users.yml"))
      end
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
      config = HallOfFame::Config.from_yaml(<<-YAML)
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
      message.should contain("grid `columns` must be >= 1")
    end

    it "parses role and group fields" do
      config = HallOfFame::Config.from_yaml(<<-YAML)
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
      config.contributors.group.should eq("Contributors")
      config.groups.should eq(["Contributors", "Special Thanks"])
    end

    it "rejects group values missing from an explicit groups list" do
      config = HallOfFame::Config.from_yaml(<<-YAML)
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
      config = HallOfFame::Config.from_yaml(<<-YAML)
        groups: [A, A, " "]
        users:
          - login: hahwul
        YAML

      error = expect_raises(HallOfFame::ConfigError) { config.validate! }
      message = error.message || ""
      message.should contain("must not be empty")
      message.should contain("duplicate `groups`")
    end

    it "rejects non-svg output paths" do
      config = HallOfFame::Config.from_yaml(<<-YAML)
        output: art.png
        users:
          - login: hahwul
        YAML

      expect_raises(HallOfFame::ConfigError, /end with .svg/) { config.validate! }
    end
  end
end

describe HallOfFame::Source do
  it "knows which sources it uses" do
    HallOfFame::Source::List.uses_list?.should be_true
    HallOfFame::Source::List.uses_contributors?.should be_false
    HallOfFame::Source::Contributors.uses_contributors?.should be_true
    HallOfFame::Source::Both.uses_list?.should be_true
    HallOfFame::Source::Both.uses_contributors?.should be_true
  end
end
