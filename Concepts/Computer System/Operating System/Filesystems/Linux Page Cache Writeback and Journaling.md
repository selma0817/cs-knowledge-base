---
aliases:
  - Page Cache and Writeback
  - Linux Journaling
tags:
  - computer-system
  - operating-system
  - linux
  - filesystem
  - prompt-caching
  - durability
created: 2026-07-19
summary: The distinction between caching file data, flushing dirty pages, and journaling multi-step filesystem metadata updates.
---
## Page cache

Linux caches file contents in memory so repeated reads do not always require storage access. The cache associates pages with a file and logical offsets; the VFS address-space object tracks cached pages and states such as dirty and writeback.[^vfs]

A cached page can be:

- **clean**: its cached contents agree with persistent storage;
- **dirty**: it has been modified in memory and may not yet be persistent;
- **under writeback**: Linux is currently transferring its changes toward storage.

## Buffered writes

A simplified buffered-write path is:

```text
application calls write()
    -> kernel accepts bytes into memory
    -> cached pages become dirty
    -> write() may return
    -> writeback happens later
    -> storage persists the data
```

A successful `write()` does not by itself guarantee that a power failure cannot lose the new bytes.[^write]

## What initiates writeback?

Linux may write dirty pages when:

- dirty data has aged;
- dirty memory crosses internal thresholds;
- memory reclaim needs space;
- background writeback workers run;
- an application explicitly requests synchronization.

`fsync(fd)` requests that modified file data and the metadata needed to retrieve it be transferred to the storage device before success is reported.[^fsync]

```text
write() success != necessarily durable
fsync() success  ~= durability requested for the relevant file state
```

The exact end-to-end guarantee still depends on the filesystem and storage stack behaving correctly.

## Writeback versus journaling

These mechanisms solve different problems:

| Mechanism | Main responsibility |
|---|---|
| Page cache | Cache reads and buffer writes in memory |
| Writeback | Transfer dirty cached data toward storage |
| Journal | Make multi-step filesystem updates recoverable after a crash |
| `fsync()` | Allow an application to wait for relevant persistence work |

The journal is not normally what triggers every dirty data page to be written.

## Why metadata needs crash recovery

Appending to a file may require multiple updates:

1. Allocate a block.
2. Write the new data.
3. Add the block to the inode mapping.
4. Increase the file size.
5. Update free-space metadata.

A crash can occur between any two steps. Without a recovery mechanism, metadata could disagree about whether a block is free or owned.

## Simplified journal transaction

```text
prepare metadata changes
    -> record transaction in journal
    -> persist a commit record
    -> copy changes to normal metadata locations
    -> later reclaim journal space
```

After a crash, the filesystem can replay complete committed transactions and discard incomplete ones.

For ext4, the default `data=ordered` mode journals metadata and orders relevant data writes before the metadata commit. `data=journal` journals both file data and metadata, while `data=writeback` provides weaker ordering between them.[^ext4]

## Structural consistency does not imply latest-data durability

After a crash, journaling may ensure that:

- block ownership metadata is coherent;
- inodes remain structurally valid;
- the filesystem can be mounted.

It does not automatically mean that every recent `write()` survived. A filesystem can be structurally consistent while the newest application data is absent.

See [[Filesystem Write Guarantees]] for the distinction between durability and consistency.

## Related notes

- [[Linux Filesystem MOC]]
- [[Linux Virtual File System Paths Directories and Inodes]]
- [[Linux File Blocks Extents and Reads]]
- [[Filesystem Write Guarantees]]
- [[Google File System]]

[^vfs]: Linux Kernel documentation, [Overview of the Linux Virtual File System](https://www.kernel.org/doc/html/latest/filesystems/vfs.html).
[^write]: Linux manual pages, [`write(2)`](https://man7.org/linux/man-pages/man2/write.2.html).
[^fsync]: Linux manual pages, [`fsync(2)`](https://man7.org/linux/man-pages/man2/fsync.2.html).
[^ext4]: Linux Kernel documentation, [ext4 Journal (jbd2)](https://www.kernel.org/doc/html/latest/filesystems/ext4/journal.html).