# sensu-du-adaptive

## Overview

An "adaptive" disk usage check plugin for Sensu

This is a fork of the original
[check-disk-usage](https://github.com/sensu-plugins/sensu-plugins-disk-checks)
plugin.

Inspired by [check_mk's](https://mathias-kettner.de/check_mk.html)
[df plugin](https://mathias-kettner.de/checkmk_filesystems.html)

Basically, a percentage threshold can vastly differ between a small volume
and a large volume.  10% free of 50GB is a lot different than 10% free of a
10TB volume.  Without setting up granular checks per-filesystem, this plugin
enables you to pass a "magic number" to adjust the base percentage depending
on volume size.

You can also provide a minimum size of volume that the adjustment will be made.

## Options

Option | Value       | Description                                | Default
------ | ----------- | ------------------------------------------ | ---------------
-c     | PERCENT     | Critical if PERCENT or more of disk full   | 95
-w     | PERCENT     | Warn if PERCENT or more of disk full       | 85
-K     | PERCENT     | Critical if PERCENT or more of inodes used | 95
-W     | PERCENT     | Warn if PERCENT or more of inodes used     | 85
-t     | TYPE[,TYPE] | Only check fs type(s)                      |
-i     | MNT[,MNT]   | Ignore mount point(s)                      |
-x     | TYPE[,TYPE] | Ignore fs type(s)                          | nfs,nfs4,nfsd,rpc_pipefs,tmpfs,devpts,sysfs,proc,binfmt_misc
-m     | MAGIC       | Magic number                               | 1.00
-l     | MINIMUM     | Minimum size to adjust (in GB)             | 100
-n     | NORMAL      | Normalize                                  | 20
-b     |             | Use line breaks in output                  | false
-v     |             | Show verbose output for OK status          | false

## Examples

__Normal usage:__

```shell
./check-du-adaptive.rb -w 90 -c 95
```

This will check all mount points (exluding the defaults) and warn if any are
over 90% used and be critical if any are over 95%.

__Adaptive usage:__

```shell
./check-du-adaptive.rb -w 90 -c 95 -m 0.9
```

This will warn at 90% utilization and be critical at 95% for disks under 100GB.
For disks larger than 100GB, the warn/critical thresolds will be adjusted.

__Verbose output:__

```shell
./check-du-adaptive.rb -w 90 -c 95 -m 0.9 -v -b
```

This will do the same as the adaptive usage example, but also be quite verbose
in its output and separate each mount with a line break.
