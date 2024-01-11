from brownie import (
    ERC20,
    MasterPriceOracle,
    ChainlinkOracle,
    USDs,
    VaultCore,
    CollateralManager,
    FeeCalculator,
    Dripper,
    RebaseManager,
    SPABuyback,
    YieldReserve,
    ProxyAdmin,
    TUP,
    Contract,
    network,
)

import json

from .utils import get_user
import eth_utils

DEPLOYMENT_ARTIFACTS = f'deployed/{network.show_active()}/deployment_data.json'
MIGRATE = True

def main():
    owner = get_user('Select deployer ')
    data = {}
    with open(DEPLOYMENT_ARTIFACTS) as file:
        data = json.load(file)

    # Deploy all the ERC20 contracts
    usdc = ERC20.at(data['USDC'])
    dai = ERC20.at(data['DAI'])
    usdt = ERC20.at(data['USDT'])
    spa = ERC20.at(data['SPA'])
    frax = ERC20.at(data['FRAX'])
    arb = ERC20.at(data['ARB'])
    lusd = ERC20.at(data['LUSD'])

    proxy_admin = Contract.from_abi('ProxyAdmin', data['proxy_admin'], ProxyAdmin.abi)
    usds = Contract.from_abi('USDs', data['usds'], USDs.abi)

    chainlink_oracle = Contract.from_abi(
        'chainlinkOracle', data['chainlink_oracle'], ChainlinkOracle.abi
    )
    master_price_oracle = Contract.from_abi(
        'MPO', data['master_price_oracle'], MasterPriceOracle.abi
    )

    vault = Contract.from_abi('Vault', data['vault'], VaultCore.abi)
    fee_calculator = Contract.from_abi(
        'FeeCalculator', data['fee_calculator'], FeeCalculator.abi
    )
    collateral_manager = Contract.from_abi(
        'CM', data['collateral_manager'], CollateralManager.abi
    )
    dripper = Contract.from_abi('Dripper', data['dripper'], Dripper.abi)
    rebase_manager = Contract.from_abi(
        'RebaseManager', data['rebase_manager'], RebaseManager.abi
    )
    spa_buyback = Contract.from_abi('SPABuyback', data['spa_buyback'], SPABuyback.abi)
    yield_reserve = Contract.from_abi(
        'YieldReserve', data['yield_reserve'], YieldReserve.abi
    )

    if (MIGRATE):
        proxy_admin.upgrade(usds, data['usds_impl'], {'from': proxy_admin.owner()})
        usds.updateVault(vault, {'from': usds.owner()})
