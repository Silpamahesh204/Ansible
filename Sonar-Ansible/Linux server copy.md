2) Linux server setup
Friday, September 25, 2026 - 11:37 AM

Reference shown: "Resizing Static Partition In Red Hat Enterprise Linux 8" (linkedin.com)

Disk inventory
--------------
[root@t0016vmsq01r01d ~]# lsblk
NAME                 SIZE TYPE MOUNTPOINT
sda                  256G disk
  sda1               500M part /boot
  sda2                63G part
    rootvg-tmplv       2G lvm  /tmp
    rootvg-usrlv      10G lvm  /usr
    rootvg-homelv      1G lvm  /home
    rootvg-varlv       8G lvm  /var
    rootvg-rootlv      2G lvm  /
  sda14                4M part
  sda15              495M part /boot/efi
sdb                   64G disk
  sdb1                64G part /mnt
sdc                  256G disk
sr0                  628K rom

Create an /apps partition and filesystem
----------------------------------------
[sonar@t0016vmsq01r01d ~]$ sudo fdisk /dev/sdc
Welcome to fdisk (util-linux 2.32.1).
Changes will remain in memory only, until you decide to write them.
Be careful before using the write command.

The first fdisk attempt created a partition in memory and ended with q, so it
was not written. The command was run again. The visible selections were:

Command (m for help): n
Partition type: p (primary)
Select (default p): p
Partition number (1-4, default 1): 1
First sector: [default 2048]
Last sector: 274877906
Created a new partition 1 of type 'Linux' and of size 131.1 GiB.
Command (m for help): w
The partition table has been altered.
Calling ioctl() to re-read partition table.
Syncing disks.

[sonar@t0016vmsq01r01d ~]$ mkfs.ext4 /dev/sdc1
Could not open /dev/sdc1: Permission denied
[sonar@t0016vmsq01r01d ~]$ sudo mkfs.ext4 /dev/sdc1
mke2fs 1.45.6 (20-Mar-2020)
Discarding device blocks: done
Creating filesystem with 34359482 4k blocks and 8593408 inodes
Filesystem UUID: df4d1905-dfd2-4895-9881-a272be4a0415
Allocating group tables: done
Writing inode tables: done
Creating journal (262144 blocks): done
Writing superblocks and filesystem accounting information: done

[sonar@t0016vmsq01r01d ~]$ cd /
[sonar@t0016vmsq01r01d /]$ sudo mkdir apps
[sonar@t0016vmsq01r01d /]$ sudo chmod 755 apps
[sonar@t0016vmsq01r01d /]$ sudo mount /dev/sdc1 apps
[sonar@t0016vmsq01r01d ~]$ df -h | grep apps
/dev/sdc1  128G  28K  122G  1%  /apps

Persist /apps in /etc/fstab
--------------------------
[sonar@t0016vmsq01r01d ~]$ lsblk -d -fs /dev/sdc1
NAME FSTYPE LABEL UUID                                 MOUNTPOINT
sdc1 ext4         df4d1905-dfd2-4895-9881-a272be4a0415 /apps

Entry to add to /etc/fstab:
UUID=df4d1905-dfd2-4895-9881-a272be4a0415 /apps ext4 defaults 0 2

[sonar@t0016vmsq01r01d ~]$ sudo vi /etc/fstab
Add the above entry at the end of the file.
[sonar@t0016vmsq01r01d ~]$ cat /etc/fstab
[The standard system entries are shown, followed by the /apps UUID entry.]

Reboot the machine to have the new mount reflected permanently:
[sonar@t0016vmsq01r01d ~]$ sudo reboot
Relogin.
[sonar@t0016vmsq01r01d ~]$ df -h
[The output confirms /dev/sdc1 mounted at /apps with 128G total and 122G available.]

Increase the root filesystem
----------------------------
Heading in video: "To increase the space of the / FS which is mounted to
/dev/mapper/rootvg-rootlv under /dev/sda2"

[sonar@t0016vmsq01r01d apps]$ lsblk /dev/sda
[The output shows /dev/sda at 256G, /dev/sda2 at 63G, and rootvg-rootlv at 2G.]

[sonar@t0016vmsq01r01d apps]$ type growpart || sudo yum install -y cloud-utils-growpart
growpart is /usr/bin/growpart

[sonar@t0016vmsq01r01d apps]$ sudo LC_ALL=en_US.UTF-8 growpart /dev/sda 2
CHANGED: partition=2 start=2050048 old: size=132165632 end=134215679
new: size=534820831 end=536870878

[sonar@t0016vmsq01r01d apps]$ sudo lvextend --size +128G --resizefs /dev/mapper/rootvg-rootlv
Size of logical volume rootvg/rootlv changed from 32.00 GiB (8192 extents)
to 160.00 GiB (40960 extents).
Logical volume rootvg/rootlv successfully resized.
Data blocks changed from 8388608 to 41943040.

[sonar@t0016vmsq01r01d apps]$ lsblk /dev/sda
[The output shows /dev/sda2 at 255G and rootvg-rootlv at 160G mounted at /.]

Prepare directories and limits for sonar
----------------------------------------
[sonar@t0016vmsq01r01d opt]$ sudo mkdir apps
[sonar@t0016vmsq01r01d home]$ sudo chown -R sonar:sonar apps

[sonar@t0016vmsq01r01d ~]$ sudo sysctl -w fs.file-max=131072
fs.file-max = 131072
[sonar@t0016vmsq01r01d ~]$ ulimit -n 131072
[sonar@t0016vmsq01r01d ~]$ ulimit -u 8192
[sonar@t0016vmsq01r01d ~]$ echo "vm.max_map_count=524288" | sudo tee -a /etc/sysctl.conf
vm.max_map_count=524288
[sonar@t0016vmsq01r01d ~]$ echo "fs.file-max=131072" | sudo tee -a /etc/sysctl.conf
fs.file-max=131072

/etc/sysctl.conf contains:
vm.max_map_count=524288
fs.file-max=131072

[sonar@t0016vmsq01r01d ~]$ echo "sonar - nofile 131072" | sudo tee -a /etc/security/limits.conf
sonar - nofile 131072
[sonar@t0016vmsq01r01d ~]$ echo "sonar - nproc 8192" | sudo tee -a /etc/security/limits.conf
sonar - nproc 8192
[sonar@t0016vmsq01r01d ~]$ cat /etc/security/limits.conf
[The default explanatory comments appear, followed by the two sonar entries.]

Check seccomp and disable IPv6
------------------------------
[sonar@t0016vmsq01r01d ~]$ grep SECCOMP /boot/config-$(uname -r)
CONFIG_HAVE_ARCH_SECCOMP_FILTER=y
CONFIG_SECCOMP_FILTER=y
CONFIG_SECCOMP=y

Heading in video: "DISABLE IPV6"
[sonar@t0016vmsq01r01d ~]$ sudo vi /etc/sysctl.conf
[sonar@t0016vmsq01r01d ~]$ sysctl -p
[Permission denied on vm.max_map_count, fs.file-max, and IPv6 keys.]
[sonar@t0016vmsq01r01d ~]$ sudo sysctl -p
vm.max_map_count = 524288
fs.file-max = 131072
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.eth0.disable_ipv6 = 1
[sonar@t0016vmsq01r01d ~]$ cat /proc/sys/net/ipv6/conf/all/disable_ipv6
1

Transcription note: The video is a moving, slightly blurred recording of a
OneNote page. Long standard command output and comments are abbreviated in
brackets. Verify disk names, UUID, sizes, and commands against the server
before applying them.
