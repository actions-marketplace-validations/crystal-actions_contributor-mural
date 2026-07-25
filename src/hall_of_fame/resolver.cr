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
      )
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
