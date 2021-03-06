require 'childprocess'
begin
  require 'byebug'
rescue LoadError
end
require_relative './base'

ChildProcess.posix_spawn = true

class TesterTimeoutError < StandardError; end
class OperationFailed < StandardError; end

class Tester < Base
  def initialize(options_or_path)
    super
    @threads = []
    @read_ops = 0
    @exception_count = 0
    @lock = Mutex.new
  end

  attr_reader :start_time
  attr_reader :exception_count

  def config_file_path
    unless @config_file_path
      raise 'Config file path was not given'
    end
    @config_file_path
  end

  def log_path
    options[:client_log] || 'client.log'
  end


  def collection
    @collection ||= client['test-collection'].with(options[:collection_options] || {})
  end

  def reader_thread_count
    options[:application_threads] || 20
  end

  def prepare
    if options[:preexec]
      options[:preexec].each do |cmd|
        execute(cmd)
      end
    end
  end

  def execute(cmd)
    if sh_cmd = cmd[:sh]
      puts "Run #{sh_cmd}"

      prefix = []
      if options[:user]
        wanted_uid = Process::UID.from_name(options[:user])
        our_uid = Process::UID.eid
        if our_uid != wanted_uid
          prefix = ['sudo', '-u', options[:user]]
        end
      end

      proc = ChildProcess.new(*prefix + ['zsh', '-c', sh_cmd])
      proc.io.inherit!
      proc.start
      proc.wait
      unless proc.exit_code == 0
        raise "Failed to execute #{cmd} (exited with code #{proc.exit_code})"
      end
    elsif cmd[:exit]
      puts "Exiting"
      @stop = true
    elsif do_cmd = cmd[:dbcmd]
      puts "Admin command: #{do_cmd}"
      logger = Logger.new(STDERR, level: Logger::WARN)
      client = Mongo::Client.new(options[:uri], logger: logger)
      if cmd[:allow_fail]
        begin
          client.database.command(do_cmd)
        rescue Mongo::Error => e
          puts "Rescued #{e.class}: #{e}"
        end
      else
        client.database.command(do_cmd)
      end
    else
      raise "Don't know what to do with #{cmd}"
    end
  end

  def target_ops
    options[:target_ops] || 100
  end

  def do_run_loop_iteration
    target_time = Time.now + 1
    ops = 0
    while Time.now < target_time
      do_one_operation_wrapped
      ops += 1
      if ops >= target_ops
        break
      end
    end
    delta = target_time - Time.now
    if delta > 0
      sleep delta
    end
  end

  def do_one_operation_wrapped
    if options[:application_timeout]
      Timeout.timeout(options[:application_timeout], TesterTimeoutError) do
        do_one_operation
      end
    else
      do_one_operation
    end
  end

  def do_one_operation
    perform_operation
    @lock.synchronize do
      @read_ops += 1
    end
  end

  def run_delegated
    reader_thread_count.times do |i|
      @threads << run_thread_loop("reader-#{i}") do
        begin
          do_run_loop_iteration
        rescue TesterTimeoutError => e
          raise "Find operation timed out by the application: #{e.class}: #{e}"
        end
        sleep 0.01
      end
    end
  end

  def run
    prepare

    logger
    client
    collection

    @start_time = Time.now

    if options[:exec]
      Thread.new do
        do_exec
      end
    end

    run_delegated

    @threads << run_thread('monitor') do
      run_monitor
    end

    Signal.trap('INT') do
      puts 'Stopping'
      @stop = true
      exit(0)
    end

    until @stop
      sleep 1
    end

    @threads.map(&:join)
  end

  def run_thread(thread_label)
    Thread.new do
      begin
        yield
      rescue => e
        puts "Unhandled exception in thread #{thread_label}: #{e.class}: #{e}"
        if options[:show_exception_traces]
          puts e.backtrace.join("\n")
        end
        @lock.synchronize do
          @exception_count += 1
        end
      end
    end
  end

  def run_thread_loop(thread_label)
    Thread.new do
      until @stop
        begin
          yield
        rescue => e
          puts "Unhandled exception in thread #{thread_label}: #{e.class}: #{e}"
          if options[:show_exception_traces]
            puts e.backtrace.join("\n")
          end
          @lock.synchronize do
            @exception_count += 1
          end
        end
      end
    end
  end

  def run_monitor
    prev_read_ops = @lock.synchronize { @read_ops }
    interval = options[:client_stats_interval] || 1
    until @stop
      sleep interval
      read_ops = @lock.synchronize do
        @read_ops
      end
      alive_threads_count = @threads.select do |thread|
        thread.alive?
      end.length
      exception_count = @lock.synchronize do
        self.exception_count
      end

      if options[:client_stats]
        now = Time.now
        puts "#{now} [+#{@now}]: #{(read_ops - prev_read_ops)/interval} read ops/sec, " +
          "#{alive_threads_count} alive threads, #{exception_count} exceptions"
        if options[:client_stats_cluster_summary]
          puts client.cluster.summary
        end
        prev_read_ops = read_ops
      end

    end
  end

  def do_exec
    @now = 0
    ops = options[:exec].to_a
    until ops.empty?
      time_delta, cmd = ops.first
      if @now >= time_delta
        puts "At #{time_delta}, run #{cmd}"
        execute(cmd)
        ops.shift
      else
        @now += 1
        sleep 1
      end
    end
  end

  def server_log_path
    options[:server_log] || 'server.log'
  end
end
