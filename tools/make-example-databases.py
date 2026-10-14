#!/usr/bin/env python3
"""Makes the example databases bin/Examples/beispiel.sqlite and
bin/Examples/beispiel.fdb from the SQL scripts next to them.

The setup program (installer/DBDesignerFork.iss) puts them into the
documents with the scripts and the models; they are not part of the
repository. Run it from the project directory before the setup is built:

    python tools/make-example-databases.py

SQLite: the script is run with sqlite3_exec of bin/sqlite3.dll (the library
the program uses; the script has triggers with ; in their body).
Firebird: isql of the Firebird kit with the embedded engine, taken from the
environment variable DBD_FIREBIRD_DIR or from ../Firebird-5.0.4-x64 next to
the project directory. An existing database file is replaced.
"""
import ctypes
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXAMPLES = os.path.join(HERE, 'bin', 'Examples')


def make_sqlite():
    script = os.path.join(EXAMPLES, 'beispiel_sqlite.sql')
    db_file = os.path.join(EXAMPLES, 'beispiel.sqlite')
    lib = ctypes.CDLL(os.path.join(HERE, 'bin', 'sqlite3.dll' if os.name == 'nt' else 'libsqlite3.so'))
    lib.sqlite3_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    lib.sqlite3_exec.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_void_p,
                                 ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p)]
    lib.sqlite3_close.argtypes = [ctypes.c_void_p]

    if os.path.exists(db_file):
        os.remove(db_file)
    db = ctypes.c_void_p()
    if lib.sqlite3_open(db_file.encode('utf-8'), ctypes.byref(db)) != 0:
        sys.exit('cannot open ' + db_file)
    try:
        err = ctypes.c_char_p()
        with open(script, encoding='utf-8') as f:
            sql = f.read()
        if lib.sqlite3_exec(db, sql.encode('utf-8'), None, None, ctypes.byref(err)) != 0:
            sys.exit('beispiel_sqlite.sql: ' + err.value.decode('utf-8', 'replace'))
    finally:
        lib.sqlite3_close(db)
    print('made', db_file)


def make_firebird():
    fb_dir = os.environ.get('DBD_FIREBIRD_DIR') or \
        os.path.join(os.path.dirname(HERE), 'Firebird-5.0.4-x64')
    isql = os.path.join(fb_dir, 'isql.exe' if os.name == 'nt' else os.path.join('bin', 'isql'))
    if not os.path.exists(isql):
        sys.exit('no isql at ' + isql + ' (set DBD_FIREBIRD_DIR)')

    script = os.path.join(EXAMPLES, 'beispiel_firebird.sql')
    db_file = os.path.join(EXAMPLES, 'beispiel.fdb')
    if os.path.exists(db_file):
        os.remove(db_file)

    # The script creates beispiel.fdb in the current directory: give it the
    # full path instead
    with open(script, encoding='utf-8') as f:
        sql = f.read()
    if "CREATE DATABASE 'beispiel.fdb'" not in sql:
        sys.exit('beispiel_firebird.sql has no CREATE DATABASE \'beispiel.fdb\'')
    sql = sql.replace("CREATE DATABASE 'beispiel.fdb'", "CREATE DATABASE '" + db_file + "'")
    tmp = tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False, encoding='utf-8')
    try:
        tmp.write(sql)
        tmp.close()
        # -b: stop at the first error, -m: errors on the output as well
        r = subprocess.run([isql, '-q', '-b', '-m', '-ch', 'UTF8', '-user', 'SYSDBA', '-i', tmp.name],
                           capture_output=True, text=True, encoding='utf-8', errors='replace')
    finally:
        os.remove(tmp.name)
    if r.returncode != 0 or 'Statement failed' in r.stdout + r.stderr:
        sys.exit('beispiel_firebird.sql:\n' + r.stdout + r.stderr)

    # Firebird may write the name in capitals; the setup takes it as it is
    for name in os.listdir(EXAMPLES):
        if name.lower() == 'beispiel.fdb' and name != 'beispiel.fdb':
            os.rename(os.path.join(EXAMPLES, name), os.path.join(EXAMPLES, 'tmp_beispiel.fdb'))
            os.rename(os.path.join(EXAMPLES, 'tmp_beispiel.fdb'), db_file)
    print('made', db_file)


if __name__ == '__main__':
    make_sqlite()
    make_firebird()
