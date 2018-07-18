require 'drb/drb'

module Psr
  # Supervisor is the process that spawns all other processes.
  # Its primary responsibility is to be a "clean slate", specifically
  # the supervisor should not ever have any of the tests loaded in its
  # address space.
  class Supervisor
    def initialize(options={})
      @concurrency = options[:concurrency] || 1
    end

    def run
      Process.setpgrp

      rd, wr = IO.pipe
      if @master_pid = fork
        # parent
        wr.close
        @master_pipe = rd
        run_supervisor
      else
        # child - master
        rd.close
        Master.new(:supervisor_pipe => wr).run
      end
    end

    def run_supervisor
    #p :run_supe
      start_time = Time.now
      @master = DRbObject.new_with_uri(MASTER_DRB_URI)
      begin
        @master.ping
      rescue DRb::DRbConnError
        if Time.now - start_time < 50
          sleep 0.5
          retry
        else
          raise
        end
      end

      @master.start

      if @master.suite_ok?
        @worker_pipes = []
        @worker_pids = []

        1.upto(@concurrency) do |i|
          rd, wr = IO.pipe
          if worker_pid = fork
            # parent
            wr.close
            @worker_pipes << rd
            @worker_pids << worker_pid
          else
            # child - worker
            rd.close
            if RSpec.world.example_groups.count > 0
              raise 'Example groups loaded too early/spilled across processes'
            end
            Worker.new(:supervisor_pipe => wr).run
            exit(0)
          end
        end

        @worker_pids.each do |pid|
          wait_for_process(pid)
        end
      end

#p :hm
      @master.dump_summary

      @master.exit
      wait_for_process(@master_pid)
    end

    def wait_for_process(pid)
      begin
        Process.wait(pid)
      rescue Errno::ECHILD
        # already dead
      end
    end
  end
end
