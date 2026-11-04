#!/usr/bin/env python3
"""Exercise packaging failure cleanup and isolation without mounting or launching."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    app = base / 'Sill Viewer.app'
    (app / 'Contents').mkdir(parents=True)
    (app / 'Contents/Info.plist').write_text('fixture')
    out = base / 'output'
    out.mkdir()
    for name in ['Sill.dmg', 'Sill.zip', 'Sill-Viewer.dmg', 'Sill-Viewer.zip']:
        (out / name).write_text('previous ' + name)
    before = {p.name: p.read_bytes() for p in out.iterdir()}
    tools = base / 'bin'
    tools.mkdir()
    hdiutil = tools / 'hdiutil'
    hdiutil.write_text('''#!/bin/bash
set -eu
if [ "$1" = create ]; then
    [ -L "${@: -2:1}/Applications" ]
    [ "$(readlink "${@: -2:1}/Applications")" = /Applications ]
    [ -d "${@: -2:1}/Sill Viewer.app" ]
    [ "$FAIL_AT" != create ] || exit 1
    echo fixture > "${@: -1}"
else
    [ "$1" = verify ]
    exit 1
fi
''')
    hdiutil.chmod(0o755)
    for failure in ['create', 'verify']:
        result = subprocess.run(['bash', str(root / 'Scripts/package-viewer.sh'), str(app), str(out)],
                                env=dict(os.environ, PATH=str(tools) + ':' + os.environ['PATH'], FAIL_AT=failure),
                                capture_output=True)
        assert result.returncode != 0, failure
        assert {p.name: p.read_bytes() for p in out.iterdir()} == before, failure
        assert (app / 'Contents/Info.plist').read_text() == 'fixture'
print('Viewer artifact failures: create/verify preserve prior artifacts and input; temporary files cleaned.')
