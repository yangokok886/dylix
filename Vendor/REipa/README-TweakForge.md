# REipa native bridge

Source: https://github.com/JRBusiness/REipa
Revision: b0d4759451ed20796892a059fa53d9dbb130af61 (0.1.0)
License: MIT, retained in LICENSE. This subset vendors reipa-macho, reipa-image,
and reipa-objc without the CLI or Swift demangler. `bridge/` is TweakForge glue.

The original local `xx_classdump.py` invoked the REipa CLI and split declarations.
The iOS implementation links these same parsing crates statically and runs entirely
in process: no Python, child processes, JIT, dlopen of user binaries, or network.
Objective-C classes, categories, typed methods and ivars are recovered from metadata.
Method implementations, standalone protocol definitions and pure Swift types are
not recovered. Encrypted images are detected and skipped, not decrypted.

Build: `python3 scripts/build_classdump.py --platform device` (or simulator/macos).
Rust stable and rustup target add aarch64-apple-ios x86_64-apple-ios are required.
Output: build/classdump-PLATFORM/libtweakforge_classdump.a; link -larchive -liconv.

Local hardening: malformed deeply nested type encodings advance to end at the
existing depth limit, preventing a method-signature loop that makes no progress.
A regression test accompanies this small vendor patch.

Resource policy: IPA entries are streamed to a private temporary file and mapped
read-only for parsing, rather than duplicated as hundreds of MB of NSData.
Limits: 4 GB input archive, 4 GB per image, 512 images / 8 GB image data,
200000 ZIP entries and 512 MB generated header text. Cancellation is checked
between archive chunks and declarations; parsing one image finishes synchronously.
Skipped/failed/encrypted images remain visible in index.json; a successful job
means at least one image yielded declarations, not that every image was exported.

License inventory: REipa MIT; Rust standard library MIT OR Apache-2.0; thiserror
MIT OR Apache-2.0. thiserror-impl, syn, quote, proc-macro2, unicode-ident are
compile-time procedural-macro dependencies rather than iOS runtime libraries.
Additional local changes: Objective-C metadata parsers skip unrelated full symbol
tables and function-start lists, reducing peak memory. Encryption preflight scans
load commands only. Duplicate class/category filenames use numbered suffixes;
index.json records original/exported pairs. All declarations are preserved.

Build96: larger mapped images, nested bundle scanning, bounded FAT64 slice decoding,
and a declaration visitor ABI avoid accumulating every header in one text buffer.
Class/category budget is 1 million declarations; a single declaration is capped
at 4 MB. Case-insensitive filename collisions receive suffixes. Old IPA export
caches are preserved in .previous-* before a new parser revision regenerates them.
