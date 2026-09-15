#!/usr/bin/env ruby

#
# <bitbar.title>Open GitHub PRs for users</bitbar.title>
# <bitbar.version>v2.0</bitbar.version>
# <bitbar.author>Tim Regener</bitbar.author>
# <bitbar.author.github>timlapluie</bitbar.author.github>
# <bitbar.desc>List all open Github PR's for the given users.</bitbar.desc>
# <bitbar.dependencies>ruby</bitbar.dependencies>
#
require 'json'
require 'net/http'

Encoding.default_external = Encoding::UTF_8

### CONFIG ###
# Create a personal access token: https://github.com/settings/tokens
# Set the GITHUB_TOKEN environment variable, or replace YOUR_TOKEN_HERE below.
GITHUB_AUTH_TOKEN = ENV.fetch('GITHUB_TOKEN', 'YOUR_TOKEN_HERE').freeze
# Optionally restrict the search to a single organization, e.g. 'my-org'
GITHUB_ORG = ''.freeze

# Show only PRs from these users
# e.g. GITHUB_USERS = ['timlapluie']
GITHUB_USERS = [].freeze
EXCLUDED_REPOS = [].freeze
### END CONFIG ###

def fetch_open_prs
  author_filters = GITHUB_USERS.map { |u| "author:#{u}" }.join(' ')
  org_filter = GITHUB_ORG.empty? ? nil : "org:#{GITHUB_ORG}"
  search_query = ["is:open is:pr", org_filter, author_filters].compact.join(' ').strip

  graphql = <<~GRAPHQL
    {
      search(query: #{search_query.inspect}, type: ISSUE, first: 100) {
        nodes {
          ... on PullRequest {
            title
            url
            createdAt
            isDraft
            mergeStateStatus
            author { login }
            repository { name url }
          }
        }
      }
    }
  GRAPHQL

  uri = URI.parse('https://api.github.com/graphql')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 10
  request = Net::HTTP::Post.new(
    uri.request_uri,
    'Authorization' => "token #{GITHUB_AUTH_TOKEN}",
    'Accept' => 'application/vnd.github.merge-info-preview+json'
  )
  request.body = { query: graphql }.to_json
  response = http.request(request)
  raise "GitHub API returned HTTP #{response.code}" unless response.code == '200'

  body = JSON.parse(response.body)
  raise "GitHub API error: #{body['errors']}" if body['errors']

  body.dig('data', 'search', 'nodes') || []
end

def state_icon(pr)
  return '🚧' if pr['isDraft']

  {
    'BEHIND'    => '🔄',
    'BLOCKED'   => '🟡',
    'CLEAN'     => '✅',
    'DIRTY'     => '⚠️',
    'HAS_HOOKS' => '🪝',
    'UNKNOWN'   => '⬛',
    'UNSTABLE'  => '❌'
  }.fetch(pr['mergeStateStatus'], '⬛')
end

def pr_line(pr)
  date = pr['createdAt'][0, 10]
  "#{state_icon(pr)}#{pr['title']} (@#{pr['author']['login']}, #{date})|href=#{pr['url']}"
end

CACHE_FILE = File.join(__dir__, '.open_github_prs_cache').freeze

begin
  open_prs = fetch_open_prs
  open_prs.reject! { |pr| EXCLUDED_REPOS.include?(pr['repository']['name']) }

  pr_details = ''
  open_prs.group_by { |pr| pr['repository']['name'] }.sort.each do |repo, prs|
    pr_details += "---\n[#{repo}]\n"
    ready, drafts = prs.partition { |pr| !pr['isDraft'] }
    ready.each { |pr| pr_details += "#{pr_line(pr)}\n" }
    if drafts.any?
      pr_details += "🚧 Drafts (#{drafts.count})\n"
      drafts.each { |pr| pr_details += "--#{pr['title']} (@#{pr['author']['login']}, #{pr['createdAt'][0, 10]})|href=#{pr['url']}\n" }
    end
  end

  output = "Open PRs (#{open_prs.count { |pr| !pr['isDraft'] }})\n#{pr_details}"
  File.write(CACHE_FILE, output, encoding: 'UTF-8')
  puts output
rescue => e
  if File.exist?(CACHE_FILE)
    title, rest = File.read(CACHE_FILE, encoding: 'UTF-8').split("\n", 2)
    puts title
    puts '---'
    puts "⚠️ Showing cached data, last fetch failed: #{e.message}"
    puts rest
  else
    puts '⚡️'
    puts '---'
    puts "Error: #{e.message}"
  end
end
