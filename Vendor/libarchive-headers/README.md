Headers from libarchive v3.7.7:

- https://github.com/libarchive/libarchive/blob/v3.7.7/libarchive/archive.h
- https://github.com/libarchive/libarchive/blob/v3.7.7/libarchive/archive_entry.h

The app links Apple's system `/usr/lib/libarchive.2.dylib`; no downloaded
libarchive executable is embedded. The headers describe the stable C API used
by `App/ArchiveImport.m`. License: `Resources/ThirdPartyNotices/libarchive-LICENSE.txt`.

The RAR reader fixtures in `tests/fixtures/` are unchanged uuencoded upstream
libarchive v3.7.7 test inputs, covered by the same license.
