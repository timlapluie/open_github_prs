#!/usr/bin/env ruby

#
# <bitbar.title>Open GitHub PRs for users</bitbar.title>
# <bitbar.version>v1.0</bitbar.version>
# <bitbar.author>Tim Regener</bitbar.author>
# <bitbar.author.github>timlapluie</bitbar.author.github>
# <bitbar.desc>List all open Github PR's for the given users.</bitbar.desc>
# <bitbar.dependencies>ruby</bitbar.dependencies>
#
require 'date'
require 'json'
require 'net/http'

### CONFIG ###
# Create a personal access token: https://github.com/settings/tokens
GITHUB_AUTH_TOKEN = 'YOUR_TOKEN_HERE'.freeze

# Show only PR's from this users
# e.g. GITHUB_USERS = ['timlapluie']
GITHUB_USERS = []
### END CONFIG ###

def get_pr_data(author)
  graphql_query = "\{user(login:\"#{author}\")\{pullRequests(states:[OPEN],last:50)\{nodes\{title,url,createdAt,mergeStateStatus,author{login},repository\{name,url\}\}\}\}\}"
  uri = URI.parse("https://api.github.com/graphql")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.request_uri, 'Authorization' => 'token ' + GITHUB_AUTH_TOKEN, 'Accept' => 'application/vnd.github.merge-info-preview+json')
  request.body = { query: graphql_query }.to_json
  response = http.request(request)
  JSON.parse(response.body).dig('data', 'user', 'pullRequests', 'nodes') || []
end

def state_icon(state)
  {
    behind: '💕',
    blocked: '💛',
    clean: '💚',
    dirty: '💔',
    draft: '🤍',
    has_hooks: '💜',
    unknown: '🖤',
    unstable: '💔'
  }[state.downcase.to_sym]
end

def pr_line(pr)
  "#{state_icon(pr['mergeStateStatus'])}#{pr['title']} (@#{pr['author']['login']}, #{Date.parse(pr['createdAt']).iso8601})|href=#{pr['url']}"
end

begin
  pr_details = ''
  open_prs = []
  GITHUB_USERS.each do |author|
    open_prs += get_pr_data(author)
  end

  open_prs = open_prs.compact.select do |pr|
    pr['url'].include?('github.com/Sage')
  end

  open_prs.group_by { |pr| pr['repository']['name'] }.sort.each do |repo, prs|
    pr_details += "---\n[#{repo}]\n"

    prs.each do |pr|
      pr_details += "#{pr_line(pr)}\n"
    end
  end

  puts "Open PRs (#{open_prs.count})"
  puts pr_details
rescue
  puts '⚡️'
  puts '---'
  puts 'An error occurred while fetching PR data.'
end
