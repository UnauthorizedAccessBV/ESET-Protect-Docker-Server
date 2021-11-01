#!/usr/bin/env python3

"""This file runs ESET PROTECT while trying
to use environment variables and docker secrets as arguments.

It also tries to deal with new install vs. upgrade automatically."""

import os
import subprocess
import time
import socket
import sys
import signal

# Time to wait for db
DB_WAIT_TIME = 300

# Default settings
SETTINGS = {
    'locale': None,
    'license-key': None,
    'server-port': None,
    'console-port': None,
    'server-root-password': 'eraadmin',
    'db-type': 'MySQL Server',
    'db-driver': 'MySQL ODBC Unicode Driver',
    'db-hostname': 'mysql',
    'db-port': '3306',
    'db-name': 'era_db',
    'db-admin-username': None,
    'db-admin-password': None,
    'db-user-username': 'era_db_user',
    'db-user-password': 'eraadmin',
    'cert-hostname': 'esmc.localhost',
    'skip-cert': None,
    'server-cert-path': None,
    'cert-auth-path': None,
    'server-cert-password': None,
    'peer-cert-password': None,
    'cert-auth-password': None,
    'cert-auth-common-name': None,
    'cert-organizational-unit': None,
    'cert-organization': None,
    'cert-locality': None,
    'cert-state': None,
    'cert-country': None,
    'cert-validity': None,
    'cert-validity-unit': None,
    'enable-imp-program': None,
    'disable-imp-program': None,
    'ad-server': None,
    'ad-user-name': None,
    'ad-user-password': None,
    'ad-cdn-include': None,
    'product-guid': None
}


class CurrentInstall:

    """Simple class for storing and updating the config"""
    def __init__(self):

        """Build class from config file"""
        self.config = {}
        self.load_config()
        self.version = None

    def load_config(self):

        """Load config file"""
        with open('/config/config.cfg', 'r') as config_file:
            for line in config_file:
                key, value = line.strip().split('=')
                self.config.update({key: value})

    def write_config(self):

        """ Write config file"""
        with open('/config/config.cfg', 'w') as config_file:
            for key, value in self.config.items():
                config_file.write(f'{key}={value}\n')


def is_new_install(current_install):

    """Check to see if this is a new install or an upgrade"""
    if current_install.config['ProductInstanceID']:
        return False

    return True


def install_database():

    """Create the database"""
    command = [
        '/opt/eset/RemoteAdministrator/Server/setup/installer_backup.sh',
        '--install-type',
        'database',
        '--skip-license',
    ]

    for key, value in SETTINGS.items():

        if value in ('1', 'true'):
            command.append('--{0}'.format(key))

        elif value in ('0', 'false'):
            continue

        elif value:
            command.extend(['--{0}'.format(key), value])

    subprocess.check_call(command)


def write_guid():

    """Write the product GUID"""
    with open('/config/config.cfg', 'r') as config_cfg:
        config_file = {}
        for line in config_cfg:
            key, value = line.split('=')
            config_file.update({key: value})

    config_file['ProductInstanceID'] = SETTINGS['product-guid'] + '\n'

    with open('/config/config.cfg', 'w') as config_cfg:
        for key, value in config_file.items():
            config_cfg.write('='.join([key, value]))


def write_startup_configuration():

    """Create the startup configuration"""
    args = [
        '--db-type',
        SETTINGS['db-type'],
        '--db-driver',
        SETTINGS['db-driver'],
        '--db-hostname',
        SETTINGS['db-hostname'],
        '--db-port',
        SETTINGS['db-port'],
        '--db-name',
        SETTINGS['db-name'],
        '--db-user-username',
        SETTINGS['db-user-username'],
        '--db-user-password',
        SETTINGS['db-user-password'],
        '--startup-config-path',
        '/config/StartupConfiguration.ini'
    ]

    custom_action('CreateStartupConfig', args)


def set_variables():

    """Check environment variables and Docker secrets to change settings"""
    for key in SETTINGS:

        env_key = key.upper().replace('-', '_')
        if env_key in os.environ:
            SETTINGS[key] = os.environ[env_key]

    if os.path.exists('/run/secrets'):

        for key in SETTINGS:

            if os.path.exists('run/secrets/{0}'.format(key)):
                SETTINGS[key] = open('/run/secrets/{0}'.format(key)).read()


def custom_action(action, args):

    """Call a custom action"""
    cmd = [
        '/opt/eset/RemoteAdministrator/Server/setup/CustomActions',
        '-a',
        action
    ]

    cmd.extend(args)

    return subprocess.check_output(cmd)


def set_guid():

    """Set the product GUID to a user-defined value"""
    if SETTINGS['product-guid']:
        return

    args = [
        '--product-name',
        'Server',
        '--db-type',
        SETTINGS['db-type'],
        '--db-driver',
        SETTINGS['db-driver'],
        '--db-hostname',
        SETTINGS['db-hostname'],
        '--db-port',
        SETTINGS['db-port'],
        '--db-name',
        SETTINGS['db-name'],
        '--db-user-username',
        SETTINGS['db-user-username'],
        '--db-user-password',
        SETTINGS['db-user-password'],
        '--db-connectors-dir',
        '/opt/eset/RemoteAdministrator/Server/setup/',
    ]

    if SETTINGS['db-admin-username'] and SETTINGS['db-admin-password']:
        args.extend([
            '--db-admin-username',
            SETTINGS['db-admin-username'],
            '--db-admin-password',
            SETTINGS['db-admin-password'],
        ])

    guid = custom_action(
        'LoadCorrectProductGuid', args
    ).rstrip().split(b'=')[1].decode()

    SETTINGS['product-guid'] = guid


def wait_for_db():

    """Wait for database port to be available"""
    host = SETTINGS['db-hostname']
    port = SETTINGS['db-port']
    start_time = time.perf_counter()

    while True:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                print('Trying database connection..')
                sock.connect((host, int(port)))
                print('Connection successful!')
                break
            except ConnectionRefusedError:
                if time.perf_counter() - start_time > DB_WAIT_TIME:
                    print('Timeout exceeded waiting for database, exiting.')
                    sys.exit(101)
                print('Database connection failed, sleeping..')
                time.sleep(5)


def is_upgrade(current_install):

    """Check to see if we need to upgrade"""
    install = '/opt/eset/RemoteAdministrator/Server/setup/installer_backup.sh'
    with open(install, 'rb') as installer:
        for line in installer:
            if line.startswith(b'arg_current_version'):
                current_version = line.strip().split(b'=')[1].split(b'"')[1]

    current_install.version = current_version.decode()
    check_version = custom_action(
        'CheckVersion',
        [
            '--installed-version', current_install.config['ProductVersion'],
            '--current-version', current_version
        ]
    ).decode()

    value = check_version.strip().split('=')[1]

    if value == "UPGRADE":
        return True

    return False


def set_upgrade_in_installer():

    """Set "is_updating" to true to set installer to update mode"""
    command = [
        '/bin/sed',
        '-i',
        's|is_updating=false|is_updating=:|',
        '/opt/eset/RemoteAdministrator/Server/setup/installer_backup.sh'
    ]

    subprocess.check_call(command)


def upgrade(current_install):

    """Upgrade the installation"""
    args = [
        '--startup-config-path', '/config/StartupConfiguration.ini',
        '--product-name', current_install.config['ProductName'],
        '--modules-dir', '/data/modules',
        '--db-connectors-dir', '/opt/eset/RemoteAdministrator/Server/setup',
        '--current-version', current_install.version
    ]

    set_upgrade_in_installer()

    load_settings = custom_action(
        'LoadInstalledData', args
    ).decode()

    current_settings = {}
    for line in load_settings.split('\n'):
        try:
            key, value = line.split('=')
            current_settings.update({key: value})
        except ValueError:
            continue

    SETTINGS['db-hostname'] = current_settings['P_DB_HOSTNAME']
    SETTINGS['db-port'] = current_settings['P_DB_PORT']

    wait_for_db()

    command = [
        '/opt/eset/RemoteAdministrator/Server/setup/installer_backup.sh',
        '--install-type', 'database',
        '--skip-license',
        '--skip-cert',
        '--db-user-username', current_settings['P_DB_ADMIN_USERNAME'],
        '--db-user-password', current_settings['P_DB_ADMIN_PASSWORD'],
        '--db-name', current_settings['P_DB_NAME'],
        '--db-hostname', current_settings['P_DB_HOSTNAME'],
        '--db-port', current_settings['P_DB_PORT'],
        '--db-driver', current_settings['P_DB_DRIVER'],
        '--db-type', current_settings['P_DB_TYPE']
    ]

    subprocess.check_call(command)

    current_install.config['ProductVersion'] = current_install.version


def bypass_root():

    """Trick for bypassing install script root check"""
    command = [
        '/bin/sed',
        '-i',
        's|`id -u`|`id -u root`|',
        '/opt/eset/RemoteAdministrator/Server/setup/installer_backup.sh'
    ]

    subprocess.check_call(command)


def killer(signum, frame):

    """Handle SIGTERM for graceful shutdowns"""
    pid = int(subprocess.check_output(['pidof', 'ERAServer']))
    os.kill(pid, signum)


def main():

    """Install ESMC database if needed and run it"""
    current_install = CurrentInstall()
    bypass_root()

    if is_new_install(current_install):
        set_variables()
        wait_for_db()
        set_guid()
        install_database()
        write_guid()
        write_startup_configuration()

    elif is_upgrade(current_install):
        upgrade(current_install)
        current_install.write_config()

    signal.signal(signal.SIGTERM, killer)
    subprocess.check_call([
        '/opt/eset/RemoteAdministrator/Server/ERAServer'
    ])


if __name__ == "__main__":
    main()
