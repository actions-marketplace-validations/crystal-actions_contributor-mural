class FakeGitHubSource < HallOfFame::GitHubSource
  getter requested_repos = [] of String
  getter requested_orgs = [] of String
  getter requested_star_repos = [] of String
  getter requested_sponsor_logins = [] of String

  def initialize(@contributors : Array(HallOfFame::ResolvedUser) = [] of HallOfFame::ResolvedUser,
                 @members : Array(HallOfFame::ResolvedUser) = [] of HallOfFame::ResolvedUser,
                 @stargazers : Array(HallOfFame::ResolvedUser) = [] of HallOfFame::ResolvedUser,
                 @sponsors : Array(HallOfFame::ResolvedUser) = [] of HallOfFame::ResolvedUser)
  end

  def contributors(repo : String) : Array(HallOfFame::ResolvedUser)
    requested_repos << repo
    @contributors
  end

  def members(org : String) : Array(HallOfFame::ResolvedUser)
    requested_orgs << org
    @members
  end

  def stargazers(repo : String) : Array(HallOfFame::ResolvedUser)
    requested_star_repos << repo
    @stargazers
  end

  def sponsors(login : String) : Array(HallOfFame::ResolvedUser)
    requested_sponsor_logins << login
    @sponsors
  end
end
