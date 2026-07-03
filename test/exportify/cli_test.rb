require 'test_helper'

class CLITest < Minitest::Test
  def test_exits_without_playlist_url
    assert_output(nil, /Usage/) do
      assert_raises(SystemExit) { Exportify::CLI.run([]) }
    end
  end

  def test_exits_with_invalid_url
    assert_raises(SystemExit) { Exportify::CLI.run(['https://open.spotify.com/album/123']) }
  end

  def test_exits_without_credentials
    ENV.delete('SPOTIFY_CLIENT_ID')
    ENV.delete('SPOTIFY_CLIENT_SECRET')

    assert_raises(SystemExit) do
      Exportify::CLI.run(['https://open.spotify.com/playlist/abc123'])
    end
  ensure
    ENV['SPOTIFY_CLIENT_ID']     = 'fake_id'
    ENV['SPOTIFY_CLIENT_SECRET'] = 'fake_secret'
  end

  def test_extracts_playlist_id_from_url
    url   = 'https://open.spotify.com/playlist/4xFRymXBprhoyr25uvyp0U?si=abc'
    match = url.match(/playlist\/([A-Za-z0-9]+)/)
    assert_equal '4xFRymXBprhoyr25uvyp0U', match&.captures&.first
  end

  def test_extracts_playlist_id_without_query_string
    url   = 'https://open.spotify.com/playlist/4xFRymXBprhoyr25uvyp0U'
    match = url.match(/playlist\/([A-Za-z0-9]+)/)
    assert_equal '4xFRymXBprhoyr25uvyp0U', match&.captures&.first
  end

  def test_default_output_dir
    assert_equal 'musics', Exportify::CLI::DEFAULT_OUTPUT_DIR
  end

  def test_output_dir_uses_playlist_name_as_subdirectory
    base     = Exportify::CLI::DEFAULT_OUTPUT_DIR
    name     = 'Rock Clássico'
    sanitized = Exportify::Downloader.sanitize(name)
    expected  = File.expand_path(File.join(base, sanitized))

    assert_equal File.expand_path('musics/Rock Clássico'), expected
  end

  def test_retag_flag_parsed_by_optionparser
    require 'optparse'
    retag = false
    argv  = ['https://open.spotify.com/playlist/abc123', '--retag']

    OptionParser.new { |opts| opts.on('--retag') { retag = true } }.parse!(argv)

    assert retag
    assert_equal ['https://open.spotify.com/playlist/abc123'], argv
  end

  def test_sync_removes_files_not_in_playlist
    require 'tmpdir'
    require 'set'

    Dir.mktmpdir do |dir|
      expected_file = File.join(dir, 'Artist - Song.mp3')
      orphan_file   = File.join(dir, 'Old Artist - Removed Song.mp3')
      FileUtils.touch(expected_file)
      FileUtils.touch(orphan_file)

      tracks = [{ artist: 'Artist', name: 'Song' }]
      expected = tracks.map do |t|
        "#{Exportify::Downloader.sanitize(t[:artist])} - #{Exportify::Downloader.sanitize(t[:name])}.mp3"
      end.to_set

      Dir.glob(File.join(dir, '*.mp3')).each do |file|
        File.delete(file) unless expected.include?(File.basename(file))
      end

      assert File.exist?(expected_file)
      refute File.exist?(orphan_file)
    end
  end

  def test_sync_flag_parsed_by_optionparser
    require 'optparse'
    sync = false
    argv = ['https://open.spotify.com/playlist/abc123', '--sync']

    OptionParser.new { |opts| opts.on('--sync') { sync = true } }.parse!(argv)

    assert sync
    assert_equal ['https://open.spotify.com/playlist/abc123'], argv
  end
end
