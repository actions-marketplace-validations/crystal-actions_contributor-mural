class FakeContributorSource < HallOfFame::ContributorSource
  getter requested_repos = [] of String

  def initialize(@users : Array(HallOfFame::ResolvedUser) = [] of HallOfFame::ResolvedUser)
  end

  def contributors(repo : String) : Array(HallOfFame::ResolvedUser)
    requested_repos << repo
    @users
  end
end
