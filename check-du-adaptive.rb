#! /usr/bin/env ruby
#
#   check-du-adaptive
#
# DESCRIPTION:
#   Uses the sys-filesystem gem to get filesystem mount points and metrics
#   Forked from https://github.com/sensu-plugins/sensu-plugins-disk-checks
#
#   Provides a more adaptive disk usage check for larger filesystems.
#   Inspired by check_mk's "df" plugin:
#     https://mathias-kettner.de/checkmk_filesystems.html
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux, BSD, Windows
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: sys-filesystem
#
# USAGE:
#
# NOTES:
#
# LICENSE:
#   Copyright 2015 Yieldbot Inc <Sensu-Plugins>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'sys/filesystem'
include Sys

#
# Check Disk
#
class CheckDisk < Sensu::Plugin::Check::CLI
  option :fstype,
         short: '-t TYPE[,TYPE]',
         description: 'Only check fs type(s)',
         proc: proc { |a| a.split(',') }

  option :ignoretype,
         short: '-x TYPE[,TYPE]',
         description: 'Ignore fs type(s)',
         proc: proc { |a| a.split(',') },
         default: 'nfs,nfs4,nfsd,rpc_pipefs,tmpfs,devpts,sysfs,proc,binfmt_misc'

  option :ignoremnt,
         short: '-i MNT[,MNT]',
         description: 'Ignore mount point(s)',
         proc: proc { |a| a.split(',') }

  option :bwarn,
         short: '-w PERCENT',
         description: 'Warn if PERCENT or more of disk full',
         proc: proc(&:to_i),
         default: 85

  option :bcrit,
         short: '-c PERCENT',
         description: 'Critical if PERCENT or more of disk full',
         proc: proc(&:to_i),
         default: 95

  option :iwarn,
         short: '-W PERCENT',
         description: 'Warn if PERCENT or more of inodes used',
         proc: proc(&:to_i),
         default: 85

  option :icrit,
         short: '-K PERCENT',
         description: 'Critical if PERCENT or more of inodes used',
         proc: proc(&:to_i),
         default: 95

  option :verbose,
         short: '-v',
         description: 'Show verbose output for OK status',
         default: false

  option :magic,
         short: '-m MAGIC',
         description: 'Magic number',
         proc: proc(&:to_f),
         default: 1.0

  option :normal,
         short: '-n NORMAL',
         description: 'Normalize',
         proc: proc(&:to_f),
         default: 20

  option :minimum,
         short: '-l MINIMUM',
         description: 'Minimum size to adjust (in GB)',
         proc: proc(&:to_f),
         default: 100

  option :linebreaks,
         short: '-b',
         description: 'Use line breaks in output',
         default: false

  # Setup variables
  #
  def initialize
    super
    @crit_fs = []
    @warn_fs = []
    @ok_fs = []
    @fs = {}
  end

  # Get mount data
  #
  def fs_mounts
    Filesystem.mounts.each do |line|
      begin
        next if config[:fstype] && !config[:fstype].include?(line.mount_type)
        next if config[:ignoretype] && config[:ignoretype].include?(line.mount_type)
        next if config[:ignoremnt] && config[:ignoremnt].include?(line.mount_point)
      rescue
        unknown 'An error occured getting the mount info'
      end
      check_mount(line)
    end
  end

  def adj_percent(size,percent)
    hsize = (size / (1024.0 * 1024.0 )) / config[:normal].to_f
    felt  = hsize ** config[:magic]
    scale = felt / hsize
    scaled = 100 - (( 100 - percent ) * scale)
    scaled

  end

  def check_mount(line)
    fs_info = Filesystem.stat(line.mount_point)
    @fs[line.mount_point] = {}
    if fs_info.respond_to?(:inodes) # needed for windows
      percent_i = percent_inodes(fs_info)
      inode_hash = {
        'total'        => fs_info.inodes,
        'free'         => fs_info.inodes_free,
        'used'         => (fs_info.inodes - fs_info.inodes_free),
        'used_percent' => percent_i,
      }
      @fs[line.mount_point]['inode'] = inode_hash

      if percent_i >= config[:icrit]
        @fs[line.mount_point]['inode']['status'] = 'critical'
        @crit_fs << @fs[line.mount_point]
      elsif percent_i >= config[:iwarn]
        @fs[line.mount_point]['inode']['status'] = 'warning'
        @warn_fs << @fs[line.mount_point]
      else
        @fs[line.mount_point]['inode']['status'] = 'ok'
        @ok_fs << @fs[line.mount_point]
      end
    end
    percent_b = percent_bytes(fs_info)

    if fs_info.bytes_total < (config[:minimum] * 1000000000)
      adj_crit = config[:bcrit]
      adj_warn = config[:bwarn]
    else
      adj_crit = adj_percent(fs_info.bytes_total,config[:bcrit])
      adj_warn = adj_percent(fs_info.bytes_total,config[:bwarn])
    end

    bytes_hash = {
      'total'        => fs_info.bytes_total,
      'free'         => fs_info.bytes_free,
      'used'         => (fs_info.bytes_total - fs_info.bytes_free),
      'used_percent' => percent_b,
      'warn_percent' => adj_warn,
      'crit_percent' => adj_crit,
      'warn_size'    => fs_info.bytes_total * (adj_warn * 0.01),
      'crit_size'    => fs_info.bytes_total * (adj_crit * 0.01),
    }
    @fs[line.mount_point]['bytes'] = bytes_hash

    if percent_b >= adj_crit
      @fs[line.mount_point]['bytes']['status'] = 'critical'
      @crit_fs << @fs[line.mount_point]
    elsif percent_b >= adj_warn
      @fs[line.mount_point]['bytes']['status'] = 'warning'
      @warn_fs << @fs[line.mount_point]
    else
      @fs[line.mount_point]['bytes']['status'] = 'ok'
      @ok_fs << @fs[line.mount_point]
    end
  end

  def bytes_to_human(s)
    prefix = %W(TiB GiB MiB KiB B)
    s = s.to_f
    i = prefix.length - 1
    while s > 512 && i > 0
      s /= 1024
      i -= 1
    end
    ((s > 9 || s.modulo(1) < 0.1 ? '%d' : '%.1f') % s) + ' ' + prefix[i]
  end

  # Determine the percent inode usage
  #
  def percent_inodes(fs_info)
    (100.0 - (100.0 * fs_info.inodes_free / fs_info.inodes)).round(2)
  end

  # Determine the percent byte usage
  #
  def percent_bytes(fs_info)
    (100.0 - (100.0 * fs_info.bytes_free / fs_info.bytes_total)).round(2)
  end

  # Generate output
  #
  def usage_summary
    x = []
    @fs.each do |fs,params|
      if config[:verbose]
        x << [
          "#{fs}: #{params['inode']['used_percent']}% inodes used ",
          "(#{params['inode']['used']} of #{params['inode']['total']}) ",
          "#{params['bytes']['used_percent']}% used ",
          "(#{bytes_to_human(params['bytes']['used'])}",
          " of #{bytes_to_human(params['bytes']['total'])}); ",
          "warn=#{params['bytes']['warn_percent'].round(2)}% ",
          "(" + bytes_to_human(params['bytes']['warn_size']).to_s + "),",
          "crit=#{params['bytes']['crit_percent'].round(2)}% ",
          "(" + bytes_to_human(params['bytes']['crit_size']).to_s + "); ",
        ].join
      else
        x << [
          "#{fs} #{params['bytes']['used_percent']}% used, ",
          "#{params['inode']['used_percent']}% inodes used; "
        ].join
      end
    end
    joinchar = config[:linebreaks] ? "\n" : ''
    x.join(joinchar)
  end

  # Main function
  #
  def run
    fs_mounts
    usage_summary
    critical usage_summary unless @crit_fs.empty?
    warning usage_summary unless @warn_fs.empty?
    ok usage_summary unless @ok_fs.empty?
  end
end
