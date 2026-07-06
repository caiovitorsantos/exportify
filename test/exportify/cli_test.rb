# frozen_string_literal: true

require 'test_helper'
require 'exportify/web_server'

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

    Exportify::Config.stub(:load, -> { {} }) do
      assert_output(nil, /exportify init/) do
        assert_raises(SystemExit) do
          Exportify::CLI.run(['https://open.spotify.com/playlist/abc123'])
        end
      end
    end
  ensure
    ENV['SPOTIFY_CLIENT_ID']     = 'fake_id'
    ENV['SPOTIFY_CLIENT_SECRET'] = 'fake_secret'
  end

  def test_init_saves_credentials_and_dir
    require 'tmpdir'
    saved = {}
    tty   = StringIO.new("#{Dir.tmpdir}/exportify_test\nmy_client_id\nmy_client_secret\n")

    Exportify::Config.stub(:load, -> { {} }) do
      Exportify::Config.stub(:save, ->(data) { saved = data }) do
        Exportify::CLI.stub(:open_tty, -> { tty }) do
          assert_output(/Configuração salva/) { Exportify::CLI.run_init }
        end
      end
    end

    assert_equal 'my_client_id',     saved['spotify_client_id']
    assert_equal 'my_client_secret', saved['spotify_client_secret']
    assert saved['output_dir']
  end

  def test_init_keeps_existing_secret_when_blank_input
    saved = {}
    cfg   = { 'spotify_client_id' => 'old_id', 'spotify_client_secret' => 'old_secret', 'output_dir' => 'musics' }
    tty   = StringIO.new("\n\n\n")

    Exportify::Config.stub(:load, -> { cfg }) do
      Exportify::Config.stub(:save, ->(data) { saved = data }) do
        Exportify::CLI.stub(:open_tty, -> { tty }) do
          assert_output(/Configuração salva/) { Exportify::CLI.run_init }
        end
      end
    end

    assert_equal 'old_id',     saved['spotify_client_id']
    assert_equal 'old_secret', saved['spotify_client_secret']
  end

  def test_extracts_playlist_id_from_url
    url   = 'https://open.spotify.com/playlist/4xFRymXBprhoyr25uvyp0U?si=abc'
    match = url.match(%r{playlist/([A-Za-z0-9]+)})

    assert_equal '4xFRymXBprhoyr25uvyp0U', match&.captures&.first
  end

  def test_extracts_playlist_id_without_query_string
    url   = 'https://open.spotify.com/playlist/4xFRymXBprhoyr25uvyp0U'
    match = url.match(%r{playlist/([A-Za-z0-9]+)})

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

    Dir.mktmpdir do |dir|
      expected_file = File.join(dir, 'Artist - Song.mp3')
      orphan_file   = File.join(dir, 'Old Artist - Removed Song.mp3')
      FileUtils.touch(expected_file)
      FileUtils.touch(orphan_file)

      tracks = [{ artist: 'Artist', name: 'Song' }]
      expected = tracks.to_set do |t|
        "#{Exportify::Downloader.sanitize(t[:artist])} - #{Exportify::Downloader.sanitize(t[:name])}.mp3"
      end

      Dir.glob(File.join(dir, '*.mp3')).each do |file|
        File.delete(file) unless expected.include?(File.basename(file))
      end

      assert_path_exists expected_file
      refute_path_exists orphan_file
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

  def test_source_for_detects_spotify
    assert_equal :spotify, Exportify::CLI.source_for('https://open.spotify.com/playlist/abc123')
  end

  def test_source_for_detects_youtube
    assert_equal :youtube, Exportify::CLI.source_for('https://www.youtube.com/playlist?list=PL123')
  end

  def test_source_for_detects_youtube_music
    assert_equal :youtube, Exportify::CLI.source_for('https://music.youtube.com/playlist?list=PL123')
  end

  def test_source_for_returns_nil_for_unknown_domain
    assert_nil Exportify::CLI.source_for('https://example.com/whatever')
  end

  def test_source_for_detects_youtube_video
    assert_equal :youtube_video, Exportify::CLI.source_for('https://www.youtube.com/watch?v=abc123')
  end

  def test_source_for_detects_youtube_video_with_mix_list_param
    assert_equal :youtube_video, Exportify::CLI.source_for('https://www.youtube.com/watch?v=abc123&list=RDabc123')
  end

  def test_source_for_returns_nil_for_watch_url_without_v_param
    assert_nil Exportify::CLI.source_for('https://www.youtube.com/watch?list=PL123')
  end

  def test_youtube_source_skips_spotify_credentials_check
    require 'tmpdir'
    ENV.delete('SPOTIFY_CLIENT_ID')
    ENV.delete('SPOTIFY_CLIENT_SECRET')

    fake_data = {
      name: 'Minha Playlist',
      tracks: [
        { artist: 'Rick Astley', all_artists: 'Rick Astley', name: 'Never Gonna Give You Up',
          raw_name: 'Never Gonna Give You Up', album: 'Minha Playlist', year: '', track_number: 1,
          genre: '', video_id: 'vid1' }
      ]
    }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:load, -> { {} }) do
        Exportify::Config.stub(:output_dir, dir) do
          Exportify::YouTube.stub(:fetch_playlist, fake_data) do
            Exportify::Downloader.stub(:download, true) do
              Exportify::Tagger.stub(:tag, true) do
                assert_output(/1 tracks found/) do
                  Exportify::CLI.run(['https://www.youtube.com/playlist?list=PL123'])
                end
              end
            end
          end
        end
      end
    end
  ensure
    ENV['SPOTIFY_CLIENT_ID']     = 'fake_id'
    ENV['SPOTIFY_CLIENT_SECRET'] = 'fake_secret'
  end

  def test_youtube_url_query_string_is_not_stripped_before_fetch
    require 'tmpdir'
    received_url = nil
    fake_data = { name: 'P', tracks: [] }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        fetch_stub = lambda do |url, **|
          received_url = url
          fake_data
        end

        Exportify::YouTube.stub(:fetch_playlist, fetch_stub) do
          Exportify::CLI.run(['https://www.youtube.com/playlist?list=PL123'])
        end
      end
    end

    assert_equal 'https://www.youtube.com/playlist?list=PL123', received_url
  end

  def test_web_subcommand_starts_server_with_default_port
    called_with = nil

    Exportify::WebServer.stub(:start, ->(port:) { called_with = port }) do
      Exportify::CLI.run(['web'])
    end

    assert_equal 4567, called_with
  end

  def test_web_subcommand_accepts_custom_port
    called_with = nil

    Exportify::WebServer.stub(:start, ->(port:) { called_with = port }) do
      Exportify::CLI.run(['web', '--port', '8080'])
    end

    assert_equal 8080, called_with
  end

  def test_download_chaptered_video_skips_when_all_files_exist
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      tracks = [
        { artist: 'Channel', name: 'Song A', video_id: 'vid1' },
        { artist: 'Channel', name: 'Song B', video_id: 'vid1' }
      ]
      FileUtils.touch(File.join(dir, 'Channel - Song A.mp3'))
      FileUtils.touch(File.join(dir, 'Channel - Song B.mp3'))

      result = nil
      Exportify::CLI.stub(:system, ->(*_args) { raise 'yt-dlp não deveria ser chamado' }) do
        result = Exportify::CLI.download_chaptered_video({ name: 'Video Title', tracks: tracks }, dir)
      end

      assert_equal({ ok: 0, skip: 2, failed: 0 }, result)
    end
  end

  def test_download_chaptered_video_downloads_renames_tags_and_cleans_up
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      tracks = [
        { artist: 'Lady Gaga', name: 'Aftersoft', video_id: 'vid1' },
        { artist: 'Lady Gaga', name: 'Cloud Nine Room', video_id: 'vid1' }
      ]
      result = nil

      Exportify::CLI.stub(
        :system,
        lambda { |*_args|
          FileUtils.touch(File.join(dir, '1 - Aftersoft.mp3'))
          FileUtils.touch(File.join(dir, '2 - Cloud Nine Room.mp3'))
          FileUtils.touch(File.join(dir, 'Full Video Title.mp3'))
          true
        }
      ) do
        Exportify::Tagger.stub(:tag, true) do
          result = Exportify::CLI.download_chaptered_video({ name: 'Full Video Title', tracks: tracks }, dir)
        end
      end

      assert_equal({ ok: 2, skip: 0, failed: 0 }, result)
      assert_path_exists File.join(dir, 'Lady Gaga - Aftersoft.mp3')
      assert_path_exists File.join(dir, 'Lady Gaga - Cloud Nine Room.mp3')
      refute_path_exists File.join(dir, 'Full Video Title.mp3')
    end
  end

  def test_download_chaptered_video_retag_mode_tags_existing_files_only
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      tracks = [
        { artist: 'Lady Gaga', name: 'Aftersoft', video_id: 'vid1' },
        { artist: 'Lady Gaga', name: 'Missing Track', video_id: 'vid1' }
      ]
      FileUtils.touch(File.join(dir, 'Lady Gaga - Aftersoft.mp3'))

      result = nil
      tagged = []

      Exportify::Tagger.stub(:tag, ->(path, _track) { tagged << path }) do
        Exportify::CLI.stub(:system, ->(*_args) { raise 'yt-dlp não deveria ser chamado em modo retag' }) do
          result = Exportify::CLI.download_chaptered_video(
            { name: 'Full Video Title', tracks: tracks }, dir, retag: true
          )
        end
      end

      assert_equal({ ok: 1, skip: 1, failed: 0 }, result)
      assert_equal [File.join(dir, 'Lady Gaga - Aftersoft.mp3')], tagged
    end
  end

  def test_youtube_video_source_with_chapters_calls_download_chaptered_video
    require 'tmpdir'

    fake_data = {
      name: 'Some Video',
      tracks: [
        { artist: 'Channel', name: 'Song A', video_id: 'vid1', chapter_start: 0.0, chapter_end: 10.0 }
      ],
      chaptered: true
    }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        Exportify::YouTube.stub(:fetch_video, fake_data) do
          fake_download = ->(_data, _output_dir, **) { { ok: 1, skip: 0, failed: 0 } }

          Exportify::CLI.stub(:download_chaptered_video, fake_download) do
            assert_output(/1 tracks found/) do
              Exportify::CLI.run(['https://www.youtube.com/watch?v=vid1'])
            end
          end
        end
      end
    end
  end

  def test_youtube_video_source_without_chapters_uses_standard_loop
    require 'tmpdir'

    fake_data = {
      name: 'Some Video',
      tracks: [
        { artist: 'Channel', name: 'Song A', video_id: 'vid1', all_artists: 'Channel', raw_name: 'Song A',
          album: 'Some Video', year: '', track_number: 1, genre: '' }
      ],
      chaptered: false
    }

    Dir.mktmpdir do |dir|
      Exportify::Config.stub(:output_dir, dir) do
        Exportify::YouTube.stub(:fetch_video, fake_data) do
          Exportify::Downloader.stub(:download, true) do
            Exportify::Tagger.stub(:tag, true) do
              assert_output(/1 tracks found/) do
                Exportify::CLI.run(['https://www.youtube.com/watch?v=vid1'])
              end
            end
          end
        end
      end
    end
  end
end
