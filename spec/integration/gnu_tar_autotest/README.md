# GNU tar Autotest scenarios

These are independent Ruby implementations of scenarios from the GNU tar **1.35**
Autotest suite. mini_tarball creates every archive under test; GNU tar and, where
applicable, bsdtar list or extract it. The shell/m4 test code and upstream archive
files are not vendored. GNU tar's original tests are copyright the Free Software
Foundation and distributed under GPL-3.0-or-later.

Sources: [GNU tar 1.35 release](https://ftp.gnu.org/gnu/tar/tar-1.35.tar.xz),
[versioned test sources](https://git.savannah.gnu.org/cgit/tar.git/tree/tests?h=v1.35).
The release archive's SHA-256 is
`4d62ff37342ec7aed748535323930c7cf94acf71c3591882b26a7ea50f3edc16`.

Every group has `gnu_tar_autotest: true` and `gnu_tar_source:` metadata containing
its upstream filename(s). With both extractors installed there are 121 examples
from 39 upstream source files. The extra examples expand boundary cases and run
shared scenarios against each reader; this is not a count of upstream tests
ported unchanged.

```sh
bundle exec rspec --tag gnu_tar_autotest
bundle exec rspec --tag gnu_tar_autotest --example long01.at
```

No source download, Autotest installation, privileged account, or GNU tar build is
needed to run the tests. GNU tar is required in CI, and bsdtar is used when
installed, as in the other integration specs.

## Source mapping and adaptations

Paths in the first column are relative to upstream `tests/`. Each example group
also names its source so that failures can be traced without this table.

| Upstream source | Local spec | Scenario and adaptation |
| --- | --- | --- |
| `long01.at` | `names_and_links_spec.rb` | Extension name ending at a 512-byte boundary followed by another member. Expanded to 99/100/101, 255/256, 511/512/513 and 1023/1024/1025-byte filenames, long symlink/hardlink names and targets, and a long directory. Upstream's original path is 511 bytes plus its terminating NUL. |
| `link01.at` | `gnu_behavior_spec.rb` | Repeated filename encoded as a hardlink to itself. Links are added explicitly; mini_tarball does not discover inode aliases. |
| `link02.at` | `names_and_links_spec.rb` | Multiple hardlinks preserve the original file's data and inode. Omits GNU tar's source deletion option. |
| `link04.at` | `names_and_links_spec.rb` | Duplicate directory/symlink members and a hardlink to a symlink. Omits automatic link detection and dereferencing. |
| `incr01.at` | `names_and_links_spec.rb` | Dangling symlink survives extraction. Only the initial archive's symlink behavior is applicable; incremental deletion is not ported. |
| `add-file.at`, `T-null2.at` | `names_and_links_spec.rb` | Verbatim dash-prefixed, space-containing and backslash-containing names. Names are passed directly to the Ruby API, not parsed from command-line options or file lists. |
| `extrac01.at` | `extraction_spec.rb` | Extraction into an existing directory keeps unrelated files. |
| `extrac02.at` | `extraction_spec.rb` | A symlink replaces an existing regular file. |
| `extrac04.at` | `selection_spec.rb` | GNU tar matches exclusion patterns against the emitted paths. |
| `extrac05.at` | `selection_spec.rb` | Selecting nonadjacent members skips intervening payloads and padding. Uses GNU format instead of the upstream PAX format. |
| `extrac06.at` | `gnu_behavior_spec.rb` | Repeated extraction honors the reader's umask. The umask is set only for the child process. |
| `extrac07.at` | `extraction_spec.rb` | A read-only directory containing a parent-relative symlink. Uses GNU format rather than USTAR; all targets stay within the temporary workspace. |
| `extrac08.at` | `extraction_spec.rb` | Archived permissions replace an existing directory's permissions. |
| `extrac10.at` | `selection_spec.rb` | Selected members can be extracted into separate destinations. |
| `extrac12.at` | `gnu_behavior_spec.rb` | A read-only `.` directory entry followed by children. |
| `extrac13.at` | `extraction_spec.rb` | Default extraction replaces an existing symlink without modifying its target. The optional dereferencing modes are not ported. |
| `extrac14.at` | `extraction_spec.rb` | The extraction destination can itself be a symlink. |
| `extrac16.at` | `extraction_spec.rb` | Nested empty directories alongside regular files. |
| `extrac17.at` | `selection_spec.rb` | Subtree selection happens before stripping path components. |
| `extrac18.at` | `selection_spec.rb` | Keep-old-files reports a collision and still extracts subsequent members. |
| `extrac20.at` | `selection_spec.rb` | Both default replacement and explicit preservation of a directory symlink. Multiple-archive collision combinations are not repeated. |
| `extrac21.at` | `gnu_behavior_spec.rb` | Delayed metadata restoration for out-of-order entries under a read-only directory. |
| `extrac22.at` | `extraction_spec.rb` | Reversed member ordering: children precede directory entries. Uses each reader's default restoration behavior, rather than GNU's explicit delay option. |
| `extrac23.at` | `selection_spec.rb` | No-overwrite-dir keeps an existing directory's metadata while extracting its child. The unreadable-directory variant is outside the portable subset. |
| `extrac24.at` | `extraction_spec.rb` | Extraction to stdout produces file contents without creating directory entries. |
| `extrac25.at` | `selection_spec.rb` | Dangling parent symlink causes an extraction error without losing the next member. |
| `recurse.at` | `extraction_spec.rb` | Explicitly adding a directory does not implicitly add files from disk. |
| `incr02.at` | `gnu_behavior_spec.rb` | Directory timestamps survive directory-first ordering, using an ordinary GNU archive with explicit delayed restoration. No incremental records or sleeps. |
| `owner.at` | `gnu_behavior_spec.rb` | Owner/group names containing spaces and punctuation are independent of numeric IDs. |
| `numeric.at` | `gnu_behavior_spec.rb` | Empty names retain numeric IDs in normal and numeric listings, expanded across the octal/base-256 boundary. |
| `time01.at` | `gnu_behavior_spec.rb` | Positive whole-second timestamps at epoch, 2038, 2106, the octal/base-256 boundary, and year 9999. Upstream PAX fractions, negative times and values beyond signed 64-bit time are excluded. Listing avoids filesystem timestamp limits. |
| `verify.at`, `difflink.at` | `gnu_behavior_spec.rb` | GNU tar compares a generated archive against disk; replacing a hardlink with a symlink is detected. Uses GNU format and `--compare` instead of writer-side `--verify`. |
| `pipe.at` | `streams_spec.rb` | Extract zero-filled and short members through stdin; additionally write mini_tarball output directly into an OS pipe. |
| `shortrec.at` | `streams_spec.rb` | Compact records are readable from disk and stdin, and empty members remain separate. |
| `compress.m4` | `streams_spec.rb` | Gzip-compressed empty member with automatic format recognition. Other compressors and suffix-based CLI selection are outside the Ruby API. |
| `comprec.at` | `streams_spec.rb` | Gzip autodetection without an extension, with streamed binary data and multiple entries. |
| `truncate.at` | `streams_spec.rb` | Short streaming writes are padded without damaging the next entry. mini_tarball raises `IncompleteWriteError` unless explicitly allowed; upstream instead warns about a shrinking source file. Deterministic streaming replaces upstream's checkpoint-timed file truncation. |

`gnu_behavior_spec.rb` and `selection_spec.rb` use GNU tar specifically because
they assert its reader policies, listing syntax or options. The other specs run
against each installed reader separately, so failures identify the reader.
In particular, bsdtar rejects self-referential hardlinks and does not apply a `.`
entry's mode to the extraction destination as GNU tar does. Those expectations
are confined to GNU tar instead of weakening the assertions or skipping failures.

## Deduplication

The ports replace 17 existing integration examples:

| Removed coverage | Replacement |
| --- | --- |
| `long_names_spec.rb` (3) | Expanded `long01.at` file and directory boundaries, including the following entry. |
| `hardlinks_spec.rb` (2) | `link02.at` and long-target `long01.at` cases. |
| `symlinks_spec.rb` (4) | `link04.at`, `extrac07.at`, and the long-name/target matrix. |
| `directories_spec.rb` (3) | `extrac16.at` empty/nested directories and `recurse.at` restricted mode. |
| `gzip_spec.rb` (2) | `compress.m4` and `comprec.at`, including non-seekable streamed content. |
| Multiple-hardlink example in `mixed_archives_spec.rb` (1) | `link02.at`, with content assertions for every link. |
| Simple and nested text examples in `regular_files_spec.rb` (2) | The extraction scenarios exercise both layouts with exact contents. |

The mixed-entry, Unicode, executable-mode, direct binary-content and writer error
recovery integration tests remain. Unit specs and GNU-generated fixture comparisons
also remain: checking exact header bytes, API behavior and errors is distinct from
checking whether an independent reader accepts the archive.

## Remaining upstream scope

The release's 237 `.at` files plus `compress.m4` were inventoried. The remaining
files fall into the categories below. A filename appearing in the mapping above
has only the stated subset ported. This is a compatibility suite for a GNU-format
writer, not a claim to implement all of GNU tar.

| Category | Files | Reason |
| --- | --- | --- |
| CLI parsing, selection and name transformation | `T-cd.at`, `T-dir00.at`, `T-dir01.at`, `T-empty.at`, `T-mult.at`, `T-nest.at`, `T-nonl.at`, `T-null.at`, `T-rec.at`, `T-recurse.at`, `T-zfile.at`, `checkpoint/defaults.at`, `checkpoint/dot-compat.at`, `checkpoint/dot-int.at`, `checkpoint/dot.at`, `checkpoint/interval.at`, `exclude.at`, `exclude01.at`, `exclude02.at`, `exclude03.at`, `exclude04.at`, `exclude05.at`, `exclude06.at`, `exclude07.at`, `exclude08.at`, `exclude09.at`, `exclude10.at`, `exclude11.at`, `exclude12.at`, `exclude13.at`, `exclude14.at`, `exclude15.at`, `exclude16.at`, `indexfile.at`, `map.at`, `opcomp01.at`, `opcomp02.at`, `opcomp03.at`, `opcomp04.at`, `opcomp05.at`, `opcomp06.at`, `options.at`, `options02.at`, `options03.at`, `positional01.at`, `positional02.at`, `positional03.at`, `recurs02.at`, `same-order01.at`, `same-order02.at`, `verbose.at`, `version.at`, `xform-h.at`, `xform01.at`, `xform02.at`, `xform03.at` | No mini_tarball CLI, file-list parser, exclusion engine, name transformation engine or checkpoint facility. |
| Editing existing archives and volume handling | `append.at`, `append01.at`, `append02.at`, `append03.at`, `append04.at`, `append05.at`, `delete01.at`, `delete02.at`, `delete03.at`, `delete04.at`, `delete05.at`, `delete06.at`, `label01.at`, `label02.at`, `label03.at`, `label04.at`, `label05.at`, `multiv01.at`, `multiv02.at`, `multiv03.at`, `multiv04.at`, `multiv05.at`, `multiv06.at`, `multiv07.at`, `multiv08.at`, `multiv09.at`, `multiv10.at`, `shortupd.at`, `update.at`, `update01.at`, `update02.at`, `update03.at`, `update04.at`, `volsize.at`, `volume.at` | No archive append/update/delete, volume labels or multivolume API. |
| Incremental archives | `chtype.at`, `incr03.at`, `incr04.at`, `incr05.at`, `incr06.at`, `incr07.at`, `incr08.at`, `incr09.at`, `incr10.at`, `incr11.at`, `incremental.at`, `listed01.at`, `listed02.at`, `listed03.at`, `listed04.at`, `listed05.at`, `rename01.at`, `rename02.at`, `rename03.at`, `rename04.at`, `rename05.at`, `rename06.at` | No snapshot database, incremental records or rename/deletion tracking. |
| Sparse files and extended metadata | `acls01.at`, `acls02.at`, `acls03.at`, `capabs_raw01.at`, `selacl01.at`, `selnx01.at`, `sparse01.at`, `sparse02.at`, `sparse03.at`, `sparse04.at`, `sparse05.at`, `sparse06.at`, `sparse07.at`, `sparsemv.at`, `sparsemvp.at`, `spmvp00.at`, `spmvp01.at`, `spmvp10.at`, `sptrcreat.at`, `sptrdiff00.at`, `sptrdiff01.at`, `xattr01.at`, `xattr02.at`, `xattr03.at`, `xattr04.at`, `xattr05.at`, `xattr06.at`, `xattr07.at`, `xattr08.at` | No sparse encoding, PAX extensions, xattrs, ACLs, SELinux labels or capabilities. |
| Other archive formats and external reader fixtures | `longv7.at`, `lustar01.at`, `lustar02.at`, `lustar03.at`, `old.at`, `star/gtarfail.at`, `star/gtarfail2.at`, `star/multi-fail.at`, `star/pax-big-10g.at`, `star/ustar-big-2g.at`, `star/ustar-big-8g.at` | V7/USTAR/PAX or downloaded reader fixtures. Existing GNU-generated unit fixtures already cover large GNU size fields; importing multi-gigabyte external archives would test the readers rather than our writer. |
| Source traversal, removal and checkpoint races | `dirrem01.at`, `dirrem02.at`, `filerem01.at`, `filerem02.at`, `grow.at`, `ignfail.at`, `link03.at`, `remfiles01.at`, `remfiles02.at`, `remfiles03.at`, `remfiles04a.at`, `remfiles04b.at`, `remfiles04c.at`, `remfiles05a.at`, `remfiles05b.at`, `remfiles05c.at`, `remfiles06a.at`, `remfiles06b.at`, `remfiles06c.at`, `remfiles07a.at`, `remfiles07b.at`, `remfiles07c.at`, `remfiles08a.at`, `remfiles08b.at`, `remfiles08c.at`, `remfiles09a.at`, `remfiles09b.at`, `remfiles09c.at`, `remfiles10.at` | No recursive filesystem scanner, remove-files option, missing-link counter or concurrent-change warning protocol. File existence and short-write errors are covered by our API specs. |
| Reader/compressor process failures | `comperr.at`, `gzip.at`, `shortfile.at`, `sigpipe.at` | Invalid input archives, compressor child-process failures and GNU CLI signal handling; mini_tarball only writes and callers supply compression. |
| Additional reader policies and resource constraints | `backup01.at`, `extrac09.at`, `extrac11.at`, `extrac15.at`, `extrac19.at`, `onetop01.at`, `onetop02.at`, `onetop03.at`, `onetop04.at`, `onetop05.at` | Backup/top-level/skip-old-files policy, unreadable ancestors, descriptor exhaustion and permission-denied extraction exercise reader internals. Existing ports cover archive structure and keep-old-files collisions without depending on resource limits or privilege. |
| Different API contract | `extrac03.at`, `time02.at` | Parent traversal in member names is deliberately rejected; automatic timestamp clamping is not exposed. Existing validator and explicit mtime specs cover our contract. |
| Autotest infrastructure | `testsuite.at` | The m4 harness itself is replaced by RSpec. |
