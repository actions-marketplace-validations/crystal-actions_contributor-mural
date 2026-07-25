module HallOfFame
  # Merges config users and API contributors into the final render list.
  # Pure: takes already-fetched contributor data, performs no IO.
  module Resolver
    def self.resolve(config : Config, api_users : Array(ResolvedUser) = [] of ResolvedUser) : Array(ResolvedUser)
      api_by_login = api_users.index_by(&.login.downcase)
      seen = Set(String).new
      result = [] of ResolvedUser

      if config.source.uses_list?
        config.users.each do |entry|
          key = entry.login.downcase
          result << from_entry(entry, api_by_login[key]?)
          seen << key
        end
      end

      if config.source.uses_contributors?
        api_users.each do |user|
          result << user if seen.add?(user.login.downcase)
        end
      end

      excluded = config.exclude.map(&.downcase).to_set
      result.reject! { |user| excluded.includes?(user.login.downcase) }
      result = sort(result, config.sort)
      config.limit.try { |lim| result = result.first(lim) }
      result
    end

    # Config entries win over API data field by field; API fills the gaps
    # (e.g. contribution count as weight, canonical avatar URL).
    private def self.from_entry(entry : UserEntry, base : ResolvedUser?) : ResolvedUser
      ResolvedUser.new(
        login: entry.login,
        name: entry.name || base.try(&.name) || entry.login,
        link: entry.link || "https://github.com/#{entry.login}",
        avatar_url: entry.avatar_url || base.try(&.avatar_url),
        weight: entry.weight || base.try(&.weight) || 1,
        role: entry.role || base.try(&.role),
        group: entry.group || base.try(&.group),
      )
    end

    # Splits embedded users into ordered (title, members) sections. Ungrouped
    # users come first without a heading; explicit `groups` fixes the order,
    # otherwise groups appear as first mentioned in the config.
    def self.grouped(users : Array(EmbeddedUser), config : Config) : Array({String?, Array(EmbeddedUser)})
      order = group_order(config)
      users.each do |user|
        order << user.group unless order.includes?(user.group)
      end
      order.compact_map do |group|
        members = users.select { |user| user.group == group }
        {group, members} unless members.empty?
      end
    end

    private def self.group_order(config : Config) : Array(String?)
      order = [nil] of String?
      if explicit = config.groups
        explicit.each { |group| order << group }
      else
        config.users.each do |user|
          if group = user.group
            order << group unless order.includes?(group)
          end
        end
        if group = config.contributors.group
          order << group unless order.includes?(group)
        end
      end
      order
    end

    private def self.sort(users : Array(ResolvedUser), mode : SortMode) : Array(ResolvedUser)
      case mode
      in .weight? then users.sort_by { |user| {-user.weight, user.login.downcase} }
      in .login?  then users.sort_by(&.login.downcase)
      in .none?   then users
      end
    end
  end
end
