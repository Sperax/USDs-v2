from brownie import (
    CustomERC20,
    MasterPriceOracle,
    ChainlinkOracle,
    DIAOracle,
    USDs,
    VaultCore,
    CollateralManager,
    FeeCalculator,
    Dripper,
    RebaseManager,
    SPABuyback,
    YieldReserve,
    AaveStrategy,
    ProxyAdmin,
    TUP,
    Contract,
    network,
)

import json

from .utils import get_user
import eth_utils

DEPLOYMENT_ARTIFACTS = f'deployed/{network.show_active()}/deployment_data.json'


def main():
    owner = get_user('Select deployer ')
    data = {}
    with open(DEPLOYMENT_ARTIFACTS) as file:
        data = json.load(file)

    # Deploy all the ERC20 contracts
    usdc = CustomERC20.at(data['USDC'])
    dai = CustomERC20.at(data['DAI'])
    usdt = CustomERC20.at(data['USDT'])
    spa = CustomERC20.at(data['SPA'])
    frax = CustomERC20.at(data['FRAX'])
    arb = CustomERC20.at(data['ARB'])
    lusd = CustomERC20.at(data['LUSD'])

    proxy_admin = Contract.from_abi('ProxyAdmin', data['proxy_admin'], ProxyAdmin.abi)
    usds = Contract.from_abi('USDs', data['usds'], USDs.abi)

    chainlink_oracle = Contract.from_abi(
        'chainlinkOracle', data['chainlink_oracle'], ChainlinkOracle.abi
    )
    master_price_oracle = Contract.from_abi(
        'MPO', data['master_price_oracle'], MasterPriceOracle.abi
    )
    dia_oracle = Contract.from_abi('DIAOracle', data['dia_oracle'], DIAOracle.abi)

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

    strategy = Contract.from_abi('mock_strategy', data['mock_strategy'], AaveStrategy.abi)