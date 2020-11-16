#!/usr/bin/env ruby

require 'open3'
require 'socket'
require 'zlib'
require 'logger'
require 'syslog/logger'
require 'net/https'
require 'json'

require '/etc/zfsendsnap.rb'

DATASET = ARGV[0]
CONF = DATASET_MAP[DATASET]
unless CONF
  raise "no configuration for #{DATASET}"
end
unless CONF[:prefix] =~ /\A[-0-9a-zA-Z_]+\z/
  raise "bad prefix."
end


PROP_PREFIX = 'me.masm11.zfsendsnap'
LOCKPID  = "#{PROP_PREFIX}:lockpid"
LASTSNAP = "#{PROP_PREFIX}:lastsnap"

sleep 15

if STDOUT.tty?
  @logger = Logger.new(STDOUT)
else
  @logger = Syslog::Logger.new 'zfsendsnap.rb'
end

def getprop(prop)
  cmd = "zfs get -H -o value #{prop} #{DATASET}"
  @logger.debug cmd
  `#{cmd}`.strip
end

def setprop(prop, value)
  cmd = "zfs set #{prop}=#{value} #{DATASET}"
  @logger.debug cmd
  system(cmd)
end

def unsetprop(prop)
  cmd = "zfs inherit #{prop} #{DATASET}"
  @logger.debug cmd
  system(cmd)
end

def snapshot(name)
  cmd = "zfs snapshot #{DATASET}@#{name}"
  @logger.debug cmd
  system(cmd)
end

def zfs_send(last, now)
  if last
    cmd = "zfs send -R -I @#{last} #{DATASET}@#{now}"
  else
    cmd = "zfs send -R #{DATASET}@#{now}"
  end
  @logger.debug cmd
  i,o, e, t = Open3.popen3(cmd)
  i.close
  return [o, e]
end

def zfs_list_snapshot
  cmd = "zfs list -t snapshot -o name -s creation -r #{DATASET}"
  @logger.debug cmd
  sss = []
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

pid = getprop(LOCKPID).to_i
if pid > 0
  begin
    Process.kill(0, pid)
  rescue Errno::ESRCH => e
    # NOP
  else
    @logger.error 'Another zfsendsnap.rb running'
    exit 1
  end
end

setprop(LOCKPID, $$)


last = getprop(LASTSNAP)
if last == '-' || last == ''
  last = nil
end

now = Time.now.localtime.strftime("#{CONF[:prefix]}%Y%m%d-%H%M%S")
@logger.info "replication #{last || '(none)'} .. #{now}"

def send_from(sock, last)
  if last
    sock.puts("#{DATASET}@#{last}")
  else
    sock.puts(DATASET)
  end
end

def send_snap(sock, last, now)
  snapshot(now)
  o, e = zfs_send(last, now)

  total_read = 0
  total_send = 0
  gz = Zlib::GzipWriter.wrap(sock)
  while (buf = o.read(1048576))
    gz.write buf
    total_read += buf.size
  end
  gz.flush
  gz.finish
  sock.shutdown Socket::SHUT_WR

  sock.each_line do |line|
    line.strip!
    return if line =~ /\Adone\z/
  end
  raise "server doesn't return done"
end

def destroy_stale(now)
  snapshots = zfs_list_snapshot
  idx = snapshots.map{|ss| ss.sub(/.*@/, '')}.index(now)
  unless idx.nil?
    snapshots[0...idx].select{|ss| ss =~ /@#{CONF[:prefix]}/ }.each do |ss|
      zfs_destroy ss
    end
  end
end

def notify_to_slack(e)
  h = {
    username: SLACK[:username],
    channel: SLACK[:channel],
    text: "Failed.```#{e.to_s}\n#{e.backtrace.join('\n')}```",
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
  @logger.debug "connecting to #{CONF[:dst][:server]} / #{CONF[:dst][:port]}"
  sock = TCPSocket.open(CONF[:dst][:server], CONF[:dst][:port])
  @logger.debug 'connecting done'

  send_from sock, last
  send_snap sock, last, now

  setprop(LASTSNAP, now)
  unsetprop(LOCKPID)

  destroy_stale now
rescue => e
  notify_to_slack e
  raise
end
