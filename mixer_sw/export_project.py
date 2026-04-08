# Copyright (c) 2026 Bogdan Petrica
# SPDX-License-Identifier: Apache-2.0
import os
import json
import fnmatch
import sys
from common import app_name, platform_name, src_dir, ws_dir
from common import find_files, dir_sync_check, dir_sync
from common import VitisClient


known_configs = [
    {'type': 'lib', 'name': 'xiltimer', 'param': 'XILTIMER_sleep_timer' },
    {'type': 'os', 'name': 'standalone', 'param': 'standalone_stdin' },
    {'type': 'os', 'name': 'standalone', 'param': 'standalone_stdout' },
]

known_user_configs = [
    'USER_COMPILE_DEFINITIONS',
    'USER_COMPILE_WARNINGS_ALL',
    'USER_COMPILE_WARNINGS_EXTRA',
    'USER_COMPILE_WARNINGS_AS_ERRORS',
    'USER_COMPILE_OPTIMIZATION_LEVEL',
    'USER_COMPILE_DEBUG_LEVEL',
    'USER_LINK_LIBRARIES',
]

ws_src_dir = os.path.join(ws_dir, app_name, 'src')


def parse_args():
    force = False
    for arg in sys.argv[1:]:
        if arg == '-f':
            force = True
    return {'force': force}


def get_domain_config(domain_name, domain):
    print(f'get domain config, domain name: "{domain_name}"')

    domain_cfg = []

    for known_config in known_configs:
        option = known_config['type']
        param = known_config['param']
        name = known_config['name']

        if option == 'lib':
            result = domain.get_config(option, param, lib_name=name)
        elif option == 'os':
            result = domain.get_config(option, param)
        else:
            assert False

        if result['value'] != result['default_value']:
            domain_cfg += [
                {
                    'type': option,
                    'name': name,
                    'param': param,
                    'value': result['value']
                }
            ]

    return domain_cfg        


def get_platform_config(platform):
    print(f'get platform config, platform: "{platform_name}"')

    platform_cfg = {}
    platform_cfg['os'] = 'standalone'
    platform_cfg['cpu'] = 'ps7_cortexa9_0'
    platform_cfg['domain_config'] = {}

    # extract platform per domain config
    for domain_dict in platform.list_domains():
        domain_name = domain_dict['domain_name']
        domain = platform.get_domain(domain_name)
        domain_cfg = get_domain_config(domain_name, domain)

        if len(domain_cfg) > 0:
            platform_cfg['domain_config'][domain_name] = domain_cfg

    return platform_cfg


def get_app_config(app, ws_src_files):
    print(f'get app config, app: "{app_name}"')

    user_compile_sources = [s.strip('"') for s in app.get_app_config('USER_COMPILE_SOURCES')]
    ws_src_header_files = [f for f in ws_src_files if fnmatch.fnmatch(f, "*.h")]

    user_cfg = []
    for known_user_config in known_user_configs:
        value = [s.strip('"') for s in app.get_app_config(known_user_config)]

        if len(value) < 1:
            continue
        elif len(value) < 2:
            value = str(value[0])
        
        user_cfg += [{'name': known_user_config, 'value': value}]

    return {
        'files': user_compile_sources + ws_src_header_files,
        'user_config': user_cfg
    }


def main():
    args = parse_args()

    cfg = {}

    print(f'initialize vitis workspace, ws_dir: "{ws_dir}"')
    with VitisClient() as client:
        client.set_workspace(ws_dir)

        platform = client.get_component(platform_name)
        cfg[platform_name] = get_platform_config(platform)

        app = client.get_component(app_name)

        ws_src_files = [f[len(ws_src_dir) + 1:] for f in find_files(ws_src_dir)]

        cfg[app_name] = get_app_config(app, ws_src_files)

        if not args['force']:
            dir_sync_check(dst_dir=src_dir, src_dir=ws_src_dir, src_files=ws_src_files)
        else:
            print('warning! forced flag pass, overriding repo files with workspace files!')
            
        dir_sync(dst_dir=src_dir, src_dir=ws_src_dir, src_files=ws_src_files)

    print('write config file, config file: config.json')
    with open('config.json', 'w') as f:
        json.dump(cfg, f, indent=True)


try:
    main()
except RuntimeError as e:
    print(f'exception {e}')
