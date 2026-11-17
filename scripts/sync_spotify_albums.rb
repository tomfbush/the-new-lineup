#!/usr/bin/env ruby
# frozen_string_literal: true

# Rewrites _data/albums.yml from the band's Spotify catalogue, newest first.
# Needs SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET in the environment.

require "base64"
require "json"
require "net/http"
require "uri"

ARTIST_ID = "6W8F3CCm6zlzfkBu9UtX8Y"
MARKET = "GB"
OUTPUT = File.expand_path("../_data/albums.yml", __dir__)

def request_json(uri, headers: {}, form: nil)
  req = form ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  headers.each { |name, value| req[name] = value }
  req.set_form_data(form) if form

  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  raise "#{uri.host} returned #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

  JSON.parse(res.body)
end

def access_token
  credentials = Base64.strict_encode64("#{ENV.fetch('SPOTIFY_CLIENT_ID')}:#{ENV.fetch('SPOTIFY_CLIENT_SECRET')}")
  body = request_json(
    URI("https://accounts.spotify.com/api/token"),
    headers: { "Authorization" => "Basic #{credentials}" },
    form: { "grant_type" => "client_credentials" }
  )
  body.fetch("access_token")
end

def artist_albums(token)
  albums = []
  uri = URI("https://api.spotify.com/v1/artists/#{ARTIST_ID}/albums?include_groups=album&market=#{MARKET}&limit=10")

  while uri
    page = request_json(uri, headers: { "Authorization" => "Bearer #{token}" })
    albums.concat(page.fetch("items"))
    uri = page["next"] && URI(page["next"])
  end

  albums
end

# Spotify lists the same album once per market, so de-duplicate by name.
def newest_first(albums)
  albums
    .sort_by { |album| album["release_date"] }
    .reverse
    .uniq { |album| album["name"] }
end

# JSON strings are valid YAML double-quoted scalars, so this avoids quoting bugs.
def render(albums)
  albums.map do |album|
    [
      "- title: #{JSON.generate(album['name'])}",
      "  spotify_id: #{album['id']}",
      "  release_date: #{JSON.generate(album['release_date'])}"
    ].join("\n")
  end.join("\n") + "\n"
end

if __FILE__ == $PROGRAM_NAME
  albums = newest_first(artist_albums(access_token))
  raise "No albums found for artist #{ARTIST_ID}; leaving #{OUTPUT} unchanged" if albums.empty?

  File.write(OUTPUT, render(albums))
  puts "Wrote #{albums.size} album(s) to #{OUTPUT}"
end
