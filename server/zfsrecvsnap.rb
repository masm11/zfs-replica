#!/usr/bin/env ruby

require 'open3'
require 'socket'
require 'zlib'
require 'logger'
require 'syslog/logger'
require 'timeout'
require 'net/https'
require 'json'

require '/etc/zfsendsnap.rb'

if STDOUT.tty?
  @logger = Logger.new(STDOUT)
else
  @logger = Syslog::Logger.new 'zfsendsnap.rb'
end

def zfs_list_snapshot
  sss = []
  cmd = "zfs list -H -t snapshot -o name -s creation -r zbak/luna"
  @logger.debug cmd
  `#{cmd}`.each_line do |line|
    sss << line.strip
  end
  sss
end

def zfs_destroy(obj)
  cmd = "zfs destroy #{obj}"
  @logger.debug cmd
  system cmd
end

def recv_from
  @from = Timeout.timeout(30) { STDIN.readline.strip }

  if @from =~ /(.*)@(.*)/
    @dataset = $1
    @dataset = DATASET_MAP[@dataset][:dst][:dataset]
    @from = $2
  else
    @dataset = from
    @dataset = DATASET_MAP[@dataset][:dst][:dataset]
    return
  end

  remove = nil
  zfs_list_snapshot.each do |line|
    line.strip!
    ss = line.sub(/.*@/, '')
    if ss == @from
      remove = []
      next
    end
    if remove.is_a? Array
      remove << line
    end
  end
  if remove.nil?
    raise "can't find #{@from}"
  end
  remove.each do |line|
    zfs_destroy line
  end
end

def log_output(f)
  f.each_line do |line|
    @logger.info line
  end
  exit 0
end

def zfs_recv
  cmd = "zfs recv -F #{@dataset}"
  @logger.debug cmd
  i, o, e, t = Open3.popen3(cmd)
  fork do
    o.close
    i.close
    log_output(e)
  end
  fork do
    e.close
    i.close
    log_output(o)
  end
  o.close
  e.close
  return [i, t]
end

def recv_snap
  i, t = zfs_recv

  gz = Timeout.timeout(30) { Zlib::GzipReader.wrap(STDIN) }
  loop do
    buf = Timeout.timeout(30) { gz.read(1048576) }
    if buf.nil?
      break
    end
    i.write buf
  end
  i.close

  if t.value != 0
    raise 'zfs recv failed.'
  end

  puts 'done'
end

def notify_to_slack(e)
  trace = e.backtrace.join("\n")
  h = {
    username: SLACK[:username],
    channel: SLACK[:channel],
    text: "Failed.```#{e.to_s}\n#{trace}```",
  }

  uri = URI.parse(SLACK[:webhook_url])
  req = Net::HTTP::Post.new(uri.path)
  req.body = JSON.dump(h)
  req['Content-Type'] = 'application/json'
  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true
  https.verify_mode = OpenSSL::SSL::VERIFY_PEER
  https.start{ https.request(req) }
end

begin
  recv_from
  recv_snap
rescue => e
  notify_to_slack e
end
