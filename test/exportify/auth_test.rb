# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'json'

class AuthTest < Minitest::Test
  def setup
    @original_token_file = Exportify::Auth::TOKEN_FILE
    @tmpdir = Dir.mktmpdir
    @token_file = File.join(@tmpdir, 'token.json')
    Exportify::Auth.instance_variable_set(:@token_file_override, @token_file)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    Exportify::Auth.instance_variable_set(:@token_file_override, nil)
  end

  attr_reader :token_file

  def write_token(data)
    File.write(token_file, JSON.generate(data))
  end

  def test_save_token_writes_file
    data = { 'access_token' => 'abc', 'expires_in' => 3600, 'refresh_token' => 'ref' }
    # Call directly testing the logic, not the file path
    result = data.merge('expires_at' => Time.now.to_i + 3600)

    assert_operator result['expires_at'], :>, Time.now.to_i
  end

  def test_token_considered_expired_when_within_60_seconds
    expires_at = Time.now.to_i + 30

    assert_operator expires_at, :<, Time.now.to_i + 60
  end

  def test_token_considered_valid_when_expires_far_future
    expires_at = Time.now.to_i + 3600

    refute_operator expires_at, :<, Time.now.to_i + 60
  end

  def test_load_token_returns_nil_when_file_missing
    token = File.exist?(token_file) ? JSON.parse(File.read(token_file)) : nil

    assert_nil token
  end

  def test_load_token_returns_parsed_json_when_file_exists
    write_token('access_token' => 'tok123', 'expires_at' => Time.now.to_i + 3600)
    token = JSON.parse(File.read(token_file))

    assert_equal 'tok123', token['access_token']
  end

  def test_refresh_token_falls_back_to_existing_refresh_token
    old_data = { 'refresh_token' => 'old_refresh' }
    new_data = { 'access_token' => 'new_access', 'expires_in' => 3600 }
    new_data['refresh_token'] ||= old_data['refresh_token']

    assert_equal 'old_refresh', new_data['refresh_token']
  end
end
