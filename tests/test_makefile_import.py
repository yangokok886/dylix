"""Integration checks of the production Makefile-to-manifest importer."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

binary = sys.argv[1]
checks = []


def prepare(root, ok=True):
    p = subprocess.run([binary, 'prepare', str(root)], text=True, capture_output=True)
    value = json.loads(p.stdout)
    assert value['ok'] == ok, value
    return json.loads((root / 'MobileCompiler.json').read_text()) if ok else value


with tempfile.TemporaryDirectory(prefix='tmc-make-') as temporary:
    base = Path(temporary)

    def fixture(name, makefile, files):
        root = base / name
        root.mkdir()
        for relative, content in files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        (root / 'Makefile').write_text(makefile)
        return root

    root = fixture('wildcard', '''export TWEAK_NAME = Example
DIR = Hooks
SOURCES = $(wildcard $(DIR)/*.xm) $(wildcard Controllers/*.m)
$(TWEAK_NAME)_FILES = $(SOURCES)
$(TWEAK_NAME)_FILES += C/Extra.c
$(TWEAK_NAME)_CFLAGS = -I$(THEOS_PROJECT_DIR)/Headers -D FIRST=1 -DSECOND=2 -include Prefix.h -O3 -w
$(TWEAK_NAME)_CCFLAGS = -std=c++14
$(TWEAK_NAME)_OBJCFLAGS = -fno-objc-arc
$(TWEAK_NAME)_FRAMEWORKS = Foundation UIKit CoreMotion
$(TWEAK_NAME)_LIBRARIES = sqlite3
$(TWEAK_NAME)_LDFLAGS = -lz -framework QuartzCore
LOGOS_DEFAULT_GENERATOR = internal
include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
''', {'Hooks/A.xm': '%ctor {}', 'Hooks/B.xm': '%ctor {}', 'Hooks/A.mm': 'stale generated code',
      'Controllers/C.m': 'int c;', 'C/Extra.c': 'int extra;', 'Headers/A.h': '', 'Prefix.h': ''})
    c = prepare(root)
    assert c['sources'] == ['Hooks/A.xm', 'Hooks/B.xm', 'Controllers/C.m', 'C/Extra.c'], c
    assert c['defines'] == ['FIRST=1', 'SECOND=2'] and 'Headers' in c['includeDirectories'], c
    assert c['forcedIncludes'] == ['Prefix.h'] and c['optimization'] == '-O3'
    assert c['cxxStandard'] == 'c++14' and c['objcArc'] is False and c['logosGenerator'] == 'internal'
    assert c['frameworks'] == ['Foundation', 'UIKit', 'CoreMotion', 'QuartzCore'] and c['libraries'] == ['sqlite3', 'z']
    checks.append('wildcard, nested variables, computed variable names, +=, flags, frameworks, libraries, generator, exclude stale generated .mm')

    root = fixture('flavors', '''TWEAK_NAME = Flavor
LATE = A.c
EARLY := $(LATE)
LATE = B.c
DEFAULT ?= C.c
DEFAULT ?= Missing.c
Flavor_FILES = $(EARLY) $(LATE)
Flavor_FILES += $(DEFAULT)
''', {'A.c': '', 'B.c': '', 'C.c': ''})
    assert prepare(root)['sources'] == ['A.c', 'B.c', 'C.c']
    checks.append('GNU Make =, :=, ?= and += evaluation order')

    root = fixture('includes', '''TWEAK_NAME = Included
include config/sources.mk
ifeq ($(SCHEME),roothide)
Included_FILES = Wrong.c
else ifeq ($(SCHEME),rootless)
Included_CFLAGS += -DROOTLESS=1
else
Included_FILES = Missing.c
endif
ifndef ABSENT
Included_FRAMEWORKS = UIKit Security
endif
-include optional.mk
''', {'config/sources.mk': 'Included_FILES = Sources/Tweak.x\n', 'Sources/Tweak.x': '%ctor {}'})
    c = prepare(root)
    assert c['sources'] == ['Sources/Tweak.x'] and c['defines'] == ['ROOTLESS=1'] and 'Security' in c['frameworks']
    checks.append('local include, optional include, rootless condition, ifndef, .x Logos source')

    root = fixture('functions', '''TWEAK_NAME = Functions
NAMES = A B
ALL = $(addprefix Sources/,$(addsuffix .c,$(NAMES)))
Functions_FILES = $(sort $(filter-out %/B.c,$(ALL)) Sources/A.c)
Functions_FILES += $(patsubst %.x,%.c,C.x)
Functions_FILES += $(subst Before,After,Before.c)
''', {'Sources/A.c': '', 'Sources/B.c': '', 'C.c': '', 'After.c': ''})
    assert prepare(root)['sources'] == ['Sources/A.c', 'C.c', 'After.c']
    checks.append('sort/filter-out/addprefix/addsuffix/patsubst/subst')

    for name, make in [
        ('shell', 'TWEAK_NAME = Unsafe\nUnsafe_FILES = $(shell touch SENTINEL; echo A.c)\n'),
        ('shell-simple', 'TWEAK_NAME = Unsafe\nUnsafe_FILES := $(shell echo A.c)\n'),
        ('cycle', 'TWEAK_NAME = Cycle\nA = $(B)\nB = $(A)\nCycle_FILES = $(A)\n'),
        ('empty-wildcard', 'TWEAK_NAME = Empty\nEmpty_FILES = $(wildcard nonexistent/*.xm)\n'),
        ('missing-source', 'TWEAK_NAME = Missing\nMissing_FILES = Missing.x\n'),
        ('multiple-targets', 'TWEAK_NAME = A B\nA_FILES = A.c\nB_FILES = A.c\n'),
        ('escaping-include', 'include ../outside.mk\n'),
        ('include-loop', 'include Makefile\n'),
        ('missing-include', 'include missing.mk\n'),
    ]:
        root = fixture(name, make, {'A.c': 'int a;'})
        prepare(root, ok=False)
        assert not (root / 'SENTINEL').exists()
        checks.append(name + ': actionable failure, no command execution or guessed source list')

    root = fixture('unsupported-flag', 'TWEAK_NAME = Flag\nFlag_FILES = A.c\nFlag_CFLAGS = $(shell echo -DBAD)\n', {'A.c': ''})
    c = prepare(root)
    assert c['sources'] == ['A.c'] and any('Flag_CFLAGS' in n for n in c['importNotes'])
    checks.append('unsupported non-source expression retained as import note')

    root = fixture('preserve-manifest', 'TWEAK_NAME = Wrong\nWrong_FILES = Missing.x\n', {'A.c': ''})
    manifest = '{"name":"Explicit","sources":["A.c"],"frameworks":[],"package":false}\n'
    (root / 'MobileCompiler.json').write_text(manifest)
    assert prepare(root)['name'] == 'Explicit'
    assert (root / 'MobileCompiler.json').read_text() == manifest
    checks.append('explicit MobileCompiler.json takes precedence and remains byte-identical')

print(json.dumps({'passed': len(checks), 'checks': checks}, indent=2))
