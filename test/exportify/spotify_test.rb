# frozen_string_literal: true

require 'test_helper'

class SpotifyTest < Minitest::Test
  FakeResponse = Struct.new(:body)

  def stub_http(body, &block)
    response = FakeResponse.new(body.to_json)
    http_conn = Minitest::Mock.new
    http_conn.expect(:request, response, [Net::HTTP::Get])

    Net::HTTP.stub(:start, ->(*_args, &block) { block.call(http_conn) }, &block)
  end

  def item(name:, artists:, album: 'Album', release_date: '2020-01-01', track_number: 1)
    {
      'item' => {
        'name' => name,
        'artists' => artists.map { |a| { 'name' => a } },
        'album' => { 'name' => album, 'release_date' => release_date },
        'track_number' => track_number
      }
    }
  end

  def test_returns_playlist_name
    stub_http({ 'name' => 'Rock Clássico' }) do
      assert_equal 'Rock Clássico', Exportify::Spotify.playlist_name('abc123', 'token')
    end
  end

  def test_returns_tracks_from_single_page
    body = { 'items' => [item(name: 'Womanizer', artists: ['Britney Spears'])], 'next' => nil }
    stub_http(body) do
      tracks = Exportify::Spotify.playlist_tracks('abc123', 'token')

      assert_equal 1, tracks.size
      assert_equal 'Womanizer', tracks.first[:name]
      assert_equal 'Britney Spears', tracks.first[:artist]
    end
  end

  def test_strips_parenthetical_from_name
    body = { 'items' => [item(name: 'WAP (feat. Megan Thee Stallion)', artists: ['Cardi B'])], 'next' => nil }
    stub_http(body) do
      tracks = Exportify::Spotify.playlist_tracks('abc123', 'token')

      assert_equal 'WAP', tracks.first[:name]
    end
  end

  def test_strips_bracket_from_name
    body = { 'items' => [item(name: 'Rush [Official]', artists: ['Troye Sivan'])], 'next' => nil }
    stub_http(body) do
      tracks = Exportify::Spotify.playlist_tracks('abc123', 'token')

      assert_equal 'Rush', tracks.first[:name]
    end
  end

  def test_strips_feat_after_dash
    body = { 'items' => [item(name: 'Song - feat. Someone', artists: ['Artist'])], 'next' => nil }
    stub_http(body) do
      tracks = Exportify::Spotify.playlist_tracks('abc123', 'token')

      assert_equal 'Song', tracks.first[:name]
    end
  end

  def test_preserves_raw_name
    body = { 'items' => [item(name: 'WAP (feat. Megan Thee Stallion)', artists: ['Cardi B'])], 'next' => nil }
    stub_http(body) do
      tracks = Exportify::Spotify.playlist_tracks('abc123', 'token')

      assert_equal 'WAP (feat. Megan Thee Stallion)', tracks.first[:raw_name]
    end
  end

  def test_joins_multiple_artists
    body = { 'items' => [item(name: 'Lady Marmalade', artists: ['Christina Aguilera', "Lil' Kim", 'Mya'])],
             'next' => nil }
    stub_http(body) do
      tracks = Exportify::Spotify.playlist_tracks('abc123', 'token')

      assert_equal "Christina Aguilera, Lil' Kim, Mya", tracks.first[:all_artists]
      assert_equal 'Christina Aguilera', tracks.first[:artist]
    end
  end

  def test_extracts_year_from_release_date
    body = { 'items' => [item(name: 'Song', artists: ['Artist'], release_date: '2019-06-14')], 'next' => nil }
    stub_http(body) do
      tracks = Exportify::Spotify.playlist_tracks('abc123', 'token')

      assert_equal '2019', tracks.first[:year]
    end
  end

  def test_skips_nil_items
    body = { 'items' => [{ 'item' => nil }, item(name: 'Valid', artists: ['Artist'])], 'next' => nil }
    stub_http(body) do
      tracks = Exportify::Spotify.playlist_tracks('abc123', 'token')

      assert_equal 1, tracks.size
      assert_equal 'Valid', tracks.first[:name]
    end
  end

  def test_enrich_with_genres_fetches_artists_individually
    tracks = [{ artist_id: 'a1' }, { artist_id: 'a2' }]
    artist_bodies = {
      'a1' => { 'id' => 'a1', 'genres' => ['pop'] },
      'a2' => { 'id' => 'a2', 'genres' => ['rock'] }
    }
    requested_paths = []

    http_conn = Object.new
    http_conn.define_singleton_method(:request) do |req|
      requested_paths << req.path
      artist_id = req.path.split('/').last
      FakeResponse.new(artist_bodies.fetch(artist_id).to_json)
    end

    result = nil
    Net::HTTP.stub(:start, ->(*_args, &block) { block.call(http_conn) }) do
      result = Exportify::Spotify.enrich_with_genres(tracks, 'token')
    end

    assert_equal(%w[/v1/artists/a1 /v1/artists/a2], requested_paths,
                 'deve buscar cada artista individualmente, sem usar o endpoint em lote /v1/artists')
    assert_equal 'pop', result[0][:genre]
    assert_equal 'rock', result[1][:genre]
  end
end
