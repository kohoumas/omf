#
# Copyright (c) 2006-2012 National ICT Australia (NICTA), Australia
#
# Copyright (c) 2004-2009 WINLAB, Rutgers University, USA
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
#
# Library of client side helpers
#
require 'fcntl'

#
# Run an application on the client.
#
# Borrows from Open3
#
class ExecApp

  # Holds the pids for all active apps
  @@all_apps = Hash.new

  # True if this active app is being killed by a proper
  # call to ExecApp.signal_all() or signal()
  # (i.e. when the caller of ExecApp decided to stop the application,
  # as far as we are concerned, this is a 'clean' exit)
  @clean_exit = false

  # Return an application instance based on its ID
  #
  # @param [String] id of the application to return
  def ExecApp.[](id)
    app = @@all_apps[id]
    logger.info "Unknown application '#{id}/#{id.class}'" if app.nil?
    return app
  end

  def ExecApp.signal_all(signal = 'KILL')
    @@all_apps.each_value { |app| app.signal(signal) }
  end

  def stdin(line)
    logger.debug "Writing '#{line}' to app '#{@id}'"
    @stdin.write("#{line}\n")
    @stdin.flush
  end

  def signal(signal = 'KILL')
    @clean_exit = true
    Process.kill(signal, @pid)
  end

  #
  # Run an application 'cmd' in a separate thread and monitor
  # its stdout. Also send status reports to the 'observer' by
  # calling its "on_app_event(eventType, appId, message")"
  #
  # @param id ID of application (used for reporting)
  # @param observer Observer of application's progress
  # @param cmd Command path and args
  # @param map_std_err_to_out If true report stderr as stdin [false]
  #
  def initialize(id, observer, cmd, map_std_err_to_out = false)

    @id = id
    @observer = observer
    @@all_apps[id] = self

    pw = IO::pipe   # pipe[0] for read, pipe[1] for write
    pr = IO::pipe
    pe = IO::pipe

    logger.debug "Starting application '#{id}' - cmd: '#{cmd}'"
    @observer.on_app_event(:STARTED, id, cmd)
    @pid = fork {
      # child will remap pipes to std and exec cmd
      pw[1].close
      STDIN.reopen(pw[0])
      pw[0].close

      pr[0].close
      STDOUT.reopen(pr[1])
      pr[1].close

      pe[0].close
      STDERR.reopen(pe[1])
      pe[1].close

      begin
        exec(cmd)
      rescue => ex
        cmd = cmd.join(' ') if cmd.kind_of?(Array)
        STDERR.puts "exec failed for '#{cmd}' (#{$!}): #{ex}"
      end
      # Should never get here
      exit!
    }

    pw[0].close
    pr[1].close
    pe[1].close
    monitor_pipe(:stdout, pr[0])
    monitor_pipe(map_std_err_to_out ? :stdout : :stderr, pe[0])
    # Create thread which waits for application to exit
    Thread.new(id, @pid) do |id, pid|
      ret = Process.waitpid(pid)
      status = $?
      @@all_apps.delete(@id)
      # app finished
      if (status == 0) || @clean_exit
        s = "OK"
        logger.debug "Application '#{id}' finished"
      else
        s = "ERROR"
        logger.debug "Application '#{id}' failed (code=#{status})"
      end
      @observer.on_app_event("DONE.#{s}", @id, "status: #{status}")
    end
    @stdin = pw[1]
  end

  private

  #
  # Create a thread to monitor the process and its output
  # and report that back to the server
  #
  # @param name Name of app stream to monitor (should be :stdout, :stderr)
  # @param pipe Pipe to read from
  #
  def monitor_pipe(name, pipe)
    Thread.new() do
      begin
        while true do
          s = pipe.readline.chomp
          @observer.on_app_event(name.to_s.upcase, @id, s)
        end
      rescue EOFError
        # do nothing
      rescue Exception => err
        logger.error "monitorApp(#{@id}): #{err}"
      ensure
        pipe.close
      end
    end
  end
end
