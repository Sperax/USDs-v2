from brownie import (
    network,
    accounts
)
import click
import sys
import time
import json
import os

class Step():
    def __init__(self, func, args, transact, contract=None, contract_addr=''):
        self.func = func
        self.args = args
        self.transact = transact
        self.contract = contract
        self.contract_addr = contract_addr


class Deployment_config():
    def __init__(
        self,
        deployment_params={},
        post_deployment_steps=[],
        upgradeable=False,
        proxy_admin=None
    ):
        self.deployment_params = deployment_params
        self.post_deployment_steps = post_deployment_steps
        self.upgradeable = upgradeable
        self.proxy_admin = proxy_admin


class Upgrade_config():
    def __init__(
        self,
        proxy_address,
        proxy_admin,
        gnosis_upgrade=True,
        post_upgrade_steps=[]
    ):
        self.proxy_address = proxy_address
        self.gnosis_upgrade = gnosis_upgrade
        self.proxy_admin = proxy_admin
        self.post_upgrade_steps = post_upgrade_steps


class Upgrade_data():
    def __init__(self, contract, config: Upgrade_config, description = ""):
        self.description= description
        self.contract = contract
        self.config = config


class Deployment_data():
    def __init__(self, contract, config: Deployment_config):
        self.contract = contract
        self.config = config




def signal_handler(signal, frame):
    sys.exit(0)


def _getYorN(msg):
    while True:
        answer = input(msg + ' [y/n] ')
        lowercase_answer = answer.lower()
        if lowercase_answer == 'y' or lowercase_answer == 'n':
            return lowercase_answer
        else:
            print('Please enter y or n.')


def get_account(msg: str):
    owner = accounts.load(
        click.prompt(
            msg,
            type=click.Choice(accounts.load())
        )
    )
    print(f'{msg}: {owner.address}\n')
    return owner


def confirm(msg):
    """
    Prompts the user to confirm an action.
    If they hit yes, nothing happens, meaning the script continues.
    If they hit no, the script exits.
    """
    answer = _getYorN(msg)
    if answer == 'y':
        return
    elif answer == 'n':
        print('Exiting...')
        exit()


def get_config(msg: str, configurations):
    configs = list(configurations.keys())
    menu = '\nPlease select config: \n'
    for i, k in enumerate(configs):
        menu += str(i) + '. ' + k + '\n'
    menu += '-> '
    config_id = int(input(menu))
    config_name = configs[config_id]
    print()
    print('-'*60, f'\nConfig selected: {config_name}')
    print('-'*60)

    return (
        config_name,
        configurations[config_name]
    )


def print_dict(msg, data, col=40):
    print('-'*70, f'\n{msg}:')
    print('-'*70)
    s = '{:<' + str(col) + '} -> {:<' + str(col//2) + '}'
    for k in data.keys():
        print(s.format(k, data[k]))
    print('-'*70, '\n')


def save_deployment_artifacts(data, name, operation_type=''):
    # Function to store deployment artifacts
    path = os.path.join('deployed', network.show_active())
    os.makedirs(path, exist_ok=True)
    file = os.path.join(
        path,
        operation_type + '_' + name + '_' +
        time.strftime('%m-%d-%Y_%H:%M:%S') + '.json'
    )
    with open(file, 'w') as json_file:
        json.dump(data, json_file, default=lambda o: o.__dict__, indent=4)
    print(f'Artifacts stored at: {file}')
