# Copyright (c) 2026 Bogdan Petrica
# SPDX-License-Identifier: Apache-2.0
import os
import json
import sys
from common import app_name, platform_name, src_dir, ws_dir
from common import find_files, dir_sync_check, dir_clean
from common import VitisClient

def parse_args():
    hw_file = None
    force = False

    i = 1
    while i < len(sys.argv):
        if sys.argv[i] == '-h':
            if i + 1 < len(sys.argv):
                hw_file = sys.argv[i+1]
                i += 2
        elif sys.argv[i] == '-f':
            force = True
            i += 1
        else:
            i += 1

    if hw_file is None:
        print(f'usage: vitis -s {sys.argv[0]} -h <hw-file> [-f]')
        sys.exit(1)

    print(f'hw file: "{hw_file}"')
    print(f'force: {force}')

    return {'hw_file': hw_file, 'force': force}


def prepare_ws_dir(args):
    ws_src_dir = os.path.join(ws_dir, app_name, 'src')
    if os.path.exists(ws_dir):
        if not os.path.isdir(ws_dir):
            raise RuntimeError(f'workspace dir path not a directory, workspace dir path: "{ws_dir}"')

    ws_src_files = []
    if os.path.exists(ws_src_dir):
        if not os.path.isdir(ws_src_dir):
            raise RuntimeError(f'workspace src dir path not a directory, workspace src dir path: "{ws_src_dir}"')
        ws_src_files = [f[len(ws_src_dir) + 1:] for f in find_files(ws_src_dir)]
    src_files = [f[len(src_dir) + 1:] for f in find_files(src_dir)]

    if not args['force']:
        # check to avoid losing modified files
        dir_sync_check(dst_dir=ws_src_dir, src_dir=src_dir, src_files=src_files)

        # check to avoid losing new files
        ws_src_only_files = set(ws_src_files) - set(src_files)
        if len(ws_src_only_files) > 0:
            raise RuntimeError(f'workspace only files detected, files: {ws_src_only_files}')
    else:
        print('warning! forced flag pass, overriding workspace files with repo files!')

    print(f'clean workspace dir, workspace dir: "{ws_dir}"')

    if os.path.exists(ws_dir):
        dir_clean(ws_dir)


def config_platform_domain(domain_name, domain, domain_cfg):
    print(f'configure platform domain, platform: "{platform_name}", domain: "{domain_name}"')

    for entry_cfg in domain_cfg:
        option = entry_cfg['type']
        name = entry_cfg['name']
        param = entry_cfg['param']
        value = entry_cfg['value']

        print(f'set config for platform domain, type: "{option}", name: "{name}", param: "{param}", value: "{value}"')
        if option == 'lib':
            domain.set_config(option,
                param=param,
                value=value,
                lib_name=name)
        elif option == 'os':
            domain.set_config(option, param=param, value=value)
        else:
            assert False


def create_platform_component(client, cfg, args):
    hw_file = args['hw_file']

    print(f'create platform component: "{platform_name}", hw_file: "{os.path.relpath(hw_file)}"')
    platform = client.create_platform_component(platform_name,
        hw_design=hw_file,
        os=cfg['platform']['os'],
        cpu=cfg['platform']['cpu'])
    client.add_platform_repos(os.path.join(ws_dir, platform_name))

    for domain_name, domain_cfg in cfg['platform']['domain_config'].items():
        domain = platform.get_domain(domain_name)
        config_platform_domain(domain_name, domain, domain_cfg)


def create_app_component(client, cfg):
    platform3_xpfm = client.find_platform_in_repos(platform_name)

    platform_domain = cfg['platform']['os'] + '_' + cfg['platform']['cpu']

    print(f'create app component: "{app_name}", xpfm: "{os.path.relpath(platform3_xpfm)}"')
    app = client.create_app_component(app_name, platform3_xpfm, domain=platform_domain)

    app.import_files(src_dir, cfg['mixer']['files'], 'src')

    for user_config in cfg['mixer']['user_config']:
        name = user_config['name']
        value = user_config['value']

        print(f'set app config, name: "{name}", value: "{value}"')
        app.set_app_config(name, value)


def import_project(cfg, args):
    prepare_ws_dir(args)

    with VitisClient() as client:
        print(f'initialize vitis workspace, workspace dir: "{ws_dir}"')
        client.set_workspace(ws_dir)
        create_platform_component(client, cfg, args)
        create_app_component(client, cfg)


def main():
    args = parse_args()
    with open('config.json', 'r') as f:
        print('load config, config file: config.json')
        cfg = json.load(f)
        import_project(cfg, args)


try:
    main()
except RuntimeError as e:
    print(f'exception {e}')
