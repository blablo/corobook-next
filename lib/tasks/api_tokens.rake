namespace :corobook do
  desc "Issue an API token: EMAIL=user@example.com [CHURCH_ID=1] NAME='pdf import' (prints the token once)"
  task issue_api_token: :environment do
    scope = User.where(email: ENV.fetch("EMAIL").strip.downcase)
    scope = scope.where(church_id: ENV["CHURCH_ID"]) if ENV["CHURCH_ID"]
    user = scope.first or abort("no such user")
    record, raw = ApiToken.issue!(user: user, name: ENV.fetch("NAME", "api"))
    puts "token ##{record.id} for #{user.email} (church ##{user.church_id}, #{user.role}):"
    puts raw
  end
end
