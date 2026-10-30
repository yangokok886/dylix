"""Exercise the production Objective-C extractor on macOS, without an iOS simulator.

Build tests/ArchiveImportCLI.m with App/ArchiveImport.m, Foundation and libarchive;
pass that executable as argv[1]. Optional uuencoded libarchive RAR fixtures follow.
"""
import binascii
import io
import json
import pathlib
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile

binary = pathlib.Path(sys.argv[1]).resolve()
results = []


def call(mode, *args, ok=True, code=None):
    process = subprocess.run([str(binary), mode, *map(str, args)], capture_output=True, text=True)
    report = json.loads(process.stdout)
    assert report["ok"] is ok, report
    if code is not None:
        assert report["code"] == code, report
    return report.get("result", report)


with tempfile.TemporaryDirectory(prefix="tmc-archives-") as work:
    root = pathlib.Path(work)
    tree = root / "tree"
    project = tree / "中文工程"
    (project / "Sources").mkdir(parents=True)
    (project / "Include").mkdir()
    (project / "Sources/Tweak.m").write_text('#import "Header.h"\nint fixture(void) { return VALUE; }\n')
    (project / "Include/Header.h").write_text("#define VALUE 42\n")
    (project / "control").write_text("Package: com.example.fixture\nName: 中文工程\nVersion: 1.0\n")
    (project / "filter.plist").write_text("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>Filter</key><dict><key>Bundles</key><array><string>com.example.host</string></array></dict></dict></plist>")
    (project / "Makefile").write_text("TWEAK_NAME = Fixture\nFixture_FILES = Sources/Tweak.m\nFixture_FRAMEWORKS = UIKit Foundation QuartzCore\nFixture_CFLAGS = -DFIXTURE=1 -IInclude -O2\n")
    (tree / "__MACOSX").mkdir()
    (tree / "__MACOSX/._ignored").write_text("metadata")

    def zip_tree(path, entries=None):
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
            if entries is not None:
                for name, data in entries:
                    archive.writestr(name, data)
            else:
                for item in tree.rglob("*"):
                    if item.is_file():
                        archive.write(item, item.relative_to(tree))

    archive = root / "project.zip"
    zip_tree(archive)
    extracted = root / "zip-output"
    call("extract", archive, extracted)
    assert (extracted / "中文工程/Include/Header.h").read_bytes() == (project / "Include/Header.h").read_bytes()
    assert not (extracted / "__MACOSX").exists()
    candidates = call("projects", extracted)
    assert len(candidates) == 1 and candidates[0]["sources"] == 1, candidates
    candidate = pathlib.Path(candidates[0]["root"])
    summary = call("prepare", candidate)
    config = json.loads((candidate / "MobileCompiler.json").read_text())
    assert summary["generatedManifest"] and config["sources"] == ["Sources/Tweak.m"]
    assert config["package"] and "QuartzCore" in config["frameworks"]
    assert config["defines"] == ["FIXTURE=1"] and config["optimization"] == "-O2"
    original_manifest = (candidate / "MobileCompiler.json").read_bytes()
    call("prepare", candidate)
    assert (candidate / "MobileCompiler.json").read_bytes() == original_manifest
    results.append("ZIP: Unicode paths, metadata skipping, nested source/headers, literal Makefile settings, manifest preservation")

    zip64 = root / "small-zip64.zip"
    with zipfile.ZipFile(zip64, "w") as archive_file:
        with archive_file.open("ZIP64.c", "w", force_zip64=True) as stream:
            stream.write(b"int zip64;\n")
    call("extract", zip64, root / "zip64-output")
    assert (root / "zip64-output/ZIP64.c").read_text() == "int zip64;\n"
    results.append("ZIP64 local headers: extracted")

    import zlib
    legacy_name = "项目/Tweak.m".encode("gbk")
    payload = b"int legacy;\n"
    crc = zlib.crc32(payload)
    local = struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, 0, 0, 0, 0, crc, len(payload), len(payload), len(legacy_name), 0) + legacy_name + payload
    central = struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20, 0, 0, 0, 0, crc, len(payload), len(payload), len(legacy_name), 0, 0, 0, 0, 0, 0) + legacy_name
    ending = struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, 1, 1, len(central), len(local), 0)
    legacy = root / "legacy.zip"
    legacy.write_bytes(local + central + ending)
    call("extract", legacy, root / "legacy-output")
    assert (root / "legacy-output/项目/Tweak.m").read_bytes() == payload
    results.append("Legacy GBK ZIP names: Chinese directory preserved")

    for suffix, mode in [("tar", "w"), ("tar.gz", "w:gz"), ("tar.bz2", "w:bz2"), ("tar.xz", "w:xz")]:
        path = root / ("project." + suffix)
        with tarfile.open(path, mode) as archive_file:
            archive_file.add(project, arcname="Wrapper/中文工程")
        destination = root / ("output-" + suffix)
        call("extract", path, destination)
        found = call("projects", destination)
        assert len(found) == 1 and found[0]["sources"] == 1
        results.append(suffix + ": real extraction and nested project recognition")

    seven = root / "project.7z"
    subprocess.run(["/usr/bin/bsdtar", "--format=7zip", "-cf", str(seven), "-C", str(project), "Sources", "Include", "control", "filter.plist"], check=True, capture_output=True)
    call("extract", seven, root / "seven-output")
    assert len(call("projects", root / "seven-output")) == 1
    results.append("7z: real extraction and project recognition")

    import gzip
    single = root / "Single.c.gz"
    with gzip.open(single, "wb") as stream:
        stream.write(b"int value(void) { return 42; }\n")
    call("extract", single, root / "single-output")
    assert (root / "single-output/Single.c").read_text().startswith("int value")
    results.append("GZIP: single compressed source filename retained")

    multiple = root / "multiple.zip"
    zip_tree(multiple, [("One/control", "Name: One"), ("One/A.m", "int a;"), ("Two/MobileCompiler.json", '{"sources":["B.c"]}'), ("Two/B.c", "int b;")])
    call("extract", multiple, root / "multiple-output")
    assert len(call("projects", root / "multiple-output")) == 2
    results.append("Multiple project roots: independently identified")

    plain = root / "plain.zip"
    zip_tree(plain, [("Repo-main/Src/A.c", "int a;"), ("Repo-main/Headers/A.h", "int a;"), ("Repo-main/Resources/data.txt", "keep")])
    call("extract", plain, root / "plain-output")
    plain_projects = call("projects", root / "plain-output")
    assert plain_projects[0]["relative"] == "Repo-main", plain_projects
    call("prepare", plain_projects[0]["root"])
    assert (root / "plain-output/Repo-main/Resources/data.txt").read_text() == "keep"
    results.append("Plain GitHub wrapper: retain headers/resources, generate recursive source config")

    for name, entries in [
        ("traversal", [("../outside.c", "bad")]),
        ("absolute", [("/outside.c", "bad")]),
        ("windows-traversal", [("..\\outside.c", "bad")]),
        ("duplicate", [("A.c", "first"), ("A.c", "second")]),
        ("case-collision", [("A.c", "first"), ("a.c", "second")]),
    ]:
        path = root / (name + ".zip")
        zip_tree(path, entries)
        destination = root / (name + "-output")
        call("extract", path, destination, ok=False, code=1)
        assert not destination.exists()
        results.append(name + ": rejected with partial extraction removed")

    for link_type, label in [(tarfile.SYMTYPE, "symlink"), (tarfile.LNKTYPE, "hardlink")]:
        path = root / (label + ".tar")
        with tarfile.open(path, "w") as archive_file:
            entry = tarfile.TarInfo("escape")
            entry.type = link_type
            entry.linkname = "../../outside"
            archive_file.addfile(entry)
        call("extract", path, root / (label + "-output"), ok=False, code=1)
        results.append(label + ": rejected")

    huge = root / "oversized.tar"
    entry = tarfile.TarInfo("Huge.c")
    entry.size = 2 * 1024**3
    huge.write_bytes(entry.tobuf() + b"\0" * 1024)
    call("extract", huge, root / "huge-output", ok=False, code=4)
    call("cancel", archive, root / "cancel-output", ok=False, code=3)
    results.append("Declared oversized entry and cancellation: bounded failures")

    invalid = root / "invalid.zip"
    invalid.write_bytes(b"This is not an archive")
    call("extract", invalid, root / "invalid-output", ok=False, code=1)
    bad_crc = root / "crc.zip"
    with zipfile.ZipFile(bad_crc, "w", zipfile.ZIP_STORED) as archive_file:
        archive_file.writestr("A.c", "int checksum;\n")
    data = bytearray(bad_crc.read_bytes())
    name_len, extra_len = struct.unpack_from("<HH", data, 26)
    data[30 + name_len + extra_len] ^= 0x40
    bad_crc.write_bytes(data)
    call("extract", bad_crc, root / "crc-output", ok=False, code=1)
    results.append("Non-archive input and bad ZIP CRC: rejected")

    secret_source = root / "Secret.c"
    secret_source.write_text("int secret;\n")
    encrypted = root / "password.zip"
    subprocess.run(["/usr/bin/zip", "-j", "-P", "fixture-password", str(encrypted), str(secret_source)], check=True, capture_output=True)
    call("extract", encrypted, root / "no-password", ok=False, code=2)
    call("extract", encrypted, root / "bad-password", "wrong", ok=False, code=2)
    call("extract", encrypted, root / "good-password", "fixture-password")
    assert (root / "good-password/Secret.c").read_bytes() == secret_source.read_bytes()
    results.append("Password ZIP: prompt condition, wrong password, correct password")

    aes = root / "aes.zip"
    subprocess.run(["/usr/bin/bsdtar", "--format=zip", "--options=zip:encryption=aes256", "--passphrase=fixture-password", "-cf", str(aes), "-C", str(root), "Secret.c"], check=True, capture_output=True)
    call("extract", aes, root / "aes-output", "fixture-password")
    assert (root / "aes-output/Secret.c").read_bytes() == secret_source.read_bytes()
    results.append("AES-256 ZIP: correct password extraction")

    malformed = root / "bad-manifest"
    malformed.mkdir()
    (malformed / "A.c").write_text("int a;")
    for config in [{"sources": ["../outside.c"]}, {"sources": ["A.c"], "frameworks": 123}, {"sources": [123]}]:
        (malformed / "MobileCompiler.json").write_text(json.dumps(config))
        call("prepare", malformed, ok=False, code=5)
    results.append("Malformed manifest and escaped source paths: rejected")

    fixture_paths = sys.argv[2:] or sorted((pathlib.Path(__file__).parent / "fixtures").glob("*.rar.uu"))
    for fixture in map(pathlib.Path, fixture_paths):
        raw = bytearray()
        active = False
        for line in fixture.read_bytes().splitlines():
            if line.startswith(b"begin "):
                active = True
                continue
            if line == b"end":
                break
            if active:
                raw.extend(binascii.a2b_uu(line))
        path = root / fixture.stem
        path.write_bytes(raw)
        destination = root / (fixture.stem + "-output")
        call("extract", path, destination)
        assert any(p.is_file() for p in destination.rglob("*"))
        results.append(fixture.name + ": upstream RAR fixture extracted")

print(json.dumps({"passed": len(results), "checks": results, "execution": "macOS production extraction code; no iOS simulator"}, ensure_ascii=False, indent=2))
