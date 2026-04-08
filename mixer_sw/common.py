# Copyright (c) 2026 Bogdan Petrica
# SPDX-License-Identifier: Apache-2.0
import vitis
import fnmatch
import os.path
import shutil

platform_name = 'platform'
app_name = 'mixer'
src_dir = 'src'
ws_dir = 'ws'

def find_files(dir):
    for entry in os.scandir(dir):
        if entry.is_file():
            if fnmatch.fnmatch(entry.name, "*.c") or fnmatch.fnmatch(entry.name, "*.h"):
                yield os.path.join(dir, entry.name)
        elif entry.is_dir() and entry.name not in [".", ".."]:
            find_files(os.path.join(dir, entry.name))


def mtime(path):
    return round(os.path.getmtime(path))


def dir_sync_check(dst_dir, src_dir, src_files):
    for file in src_files:
        dst_file = os.path.join(dst_dir, file)
        src_file = os.path.join(src_dir, file)

        if os.path.exists(dst_file):
            if not os.path.isfile(dst_file):
                raise RuntimeError(f'dst file path exists, not a file object, dst_file: "{dst_file}"')
            
            if mtime(dst_file) > mtime(src_file):
                raise RuntimeError(f'destination file newer, dst_file: "{dst_file}", src_file: "{src_file}"')


def dir_sync(dst_dir, src_dir, src_files):
    print(f'dir sync, dst_dir: "{dst_dir}", src_dir: "{src_dir}"')

    for file in src_files:
        dst_file = os.path.join(dst_dir, file)
        src_file = os.path.join(src_dir, file)

        print(f'copy src_file: "{src_file}", dst_file: "{dst_file}"')
        shutil.copy2(src_file, dst_file)


def dir_clean(name):
    assert os.path.isdir(name)

    for entry in os.scandir(name):
        if entry.is_file():
            os.remove(os.path.join(name, entry.name))
        elif entry.is_dir() and entry.name not in [".", ".."]:
            dir_clean(os.path.join(name, entry.name))
            os.rmdir(os.path.join(name, entry.name))


class VitisClient:
    def __init__(self):
        self.client = vitis.create_client()

    def __enter__(self):
        return self.client
    
    def __exit__(self, exc_type, exc_value, tb):
        self.client.close()
        vitis.dispose()
        return False
