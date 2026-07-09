# frozen_string_literal: true

require 'open3'
require 'securerandom'

module Exportify
  module Jobs
    module_function

    @jobs = {}
    @registry_mutex = Mutex.new

    def start(cmd)
      job_id = SecureRandom.hex(8)
      job = { status: 'running', log: [], mutex: Mutex.new }

      @registry_mutex.synchronize { @jobs[job_id] = job }

      Thread.new { run(job, cmd) }

      job_id
    end

    def status(job_id)
      job = @registry_mutex.synchronize { @jobs[job_id] }
      return nil unless job

      job[:mutex].synchronize { { status: job[:status], log: job[:log].dup } }
    end

    def run(job, cmd)
      Open3.popen2e(*cmd) do |_stdin, stdout_err, wait_thread|
        stdout_err.each_line do |line|
          job[:mutex].synchronize { job[:log] << line.chomp }
        end

        job[:mutex].synchronize { job[:status] = wait_thread.value.success? ? 'done' : 'error' }
      end
    rescue StandardError => e
      job[:mutex].synchronize do
        job[:log] << "Erro: #{e.message}"
        job[:status] = 'error'
      end
    end
  end
end
