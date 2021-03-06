class MessageBus::TimerThread

  attr_reader :jobs

  class Cancelable
    NOOP = proc{}

    def initialize(job)
      @job = job
    end
    def cancel
      @job[1] = NOOP
    end
  end

  def initialize
    @stopped = false
    @jobs = []
    @mutex = Mutex.new
    @next = nil
    @thread = Thread.new{do_work}
    @on_error = lambda{|e| STDERR.puts "Exception while processing Timer:\n #{e.backtrace.join("\n")}"}
  end

  def stop
    @stopped = true
  end

  # queue a block to run after a certain delay (in seconds)
  def queue(delay=0, &block)
    queue_time = Time.new.to_f + delay
    job = [queue_time, block]

    @mutex.synchronize do
      i = @jobs.length
      while i > 0
        i -= 1
        current,_ = @jobs[i]
        i+=1 and break if current < queue_time
      end
      @jobs.insert(i, job)
      @next = queue_time if i==0
    end

    unless @thread.alive?
      @mutex.synchronize do
        @thread = Thread.new{do_work} unless @thread.alive?
      end
    end

    if @thread.status == "sleep".freeze
      @thread.wakeup
    end

    Cancelable.new(job)
  end

  def on_error(&block)
    @on_error = block
  end

  protected

  def do_work
    while !@stopped
      if @next && @next <= Time.new.to_f
        _,blk = @jobs.shift
        begin
          blk.call
        rescue => e
          @on_error.call(e) if @on_error
        end
        @mutex.synchronize do
          @next,_ = @jobs[0]
        end
      end
      unless @next && @next <= Time.new.to_f
        sleep_time = 1000
        @mutex.synchronize do
          sleep_time = @next-Time.new.to_f if @next
        end
        sleep [0,sleep_time].max
      end
    end
  end

end
