# frozen_string_literal: true

require 'test_helper'
require 'exportify/jobs'

class JobsTest < Minitest::Test
  def test_start_returns_job_id_and_status_becomes_done_with_captured_log
    job_id = Exportify::Jobs.start(['ruby', '-e', "puts 'line1'; puts 'line2'"])

    result = wait_for_completion(job_id)

    assert_equal 'done', result[:status]
    assert_equal %w[line1 line2], result[:log]
  end

  def test_start_marks_status_error_on_non_zero_exit
    job_id = Exportify::Jobs.start(['ruby', '-e', 'exit 1'])

    result = wait_for_completion(job_id)

    assert_equal 'error', result[:status]
  end

  def test_status_returns_nil_for_unknown_job_id
    assert_nil Exportify::Jobs.status('does-not-exist')
  end

  def test_status_reports_running_before_completion
    job_id = Exportify::Jobs.start(['ruby', '-e', 'sleep 1'])

    assert_equal 'running', Exportify::Jobs.status(job_id)[:status]
  end

  private

  def wait_for_completion(job_id, timeout: 5)
    deadline = Time.now + timeout

    loop do
      result = Exportify::Jobs.status(job_id)
      return result if result[:status] != 'running'
      raise "job #{job_id} não terminou em #{timeout}s" if Time.now > deadline

      sleep 0.02
    end
  end
end
