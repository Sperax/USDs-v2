from brownie import (
    MasterPriceOracle,
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
USDS_OWNER_ADDR = "0x5b12d9846F8612E439730d18E1C12634753B1bF1"
PUBLISH_SRC = False

class Token:
    def __init__(self, name, symbol, decimals):
        self.name = name
        self.symbol = symbol
        self.decimals = decimals


class CollateralData:
    def __init__(
        self,
        address,
        mint_allowed,
        redeem_allowed,
        allocation_allowed,
        base_fee_in,
        base_fee_out,
        downside_peg,
        desired_collateral_composition,
    ):
        self.address = address
        self.mint_allowed = mint_allowed
        self.redeem_allowed = redeem_allowed
        self.allocation_allowed = allocation_allowed
        self.base_fee_in = base_fee_in
        self.base_fee_out = base_fee_out
        self.downside_peg = downside_peg
        self.desired_collateral_composition = desired_collateral_composition


def deploy(deployments, contract, args, key):
    if key in deployments.keys():
        print(f'\n Using pre-deployed {key}\n')
        return contract.at(deployments[key]), False
    else:
        return contract.deploy(*args, publish_source=PUBLISH_SRC), True


def main():
    owner = get_user('Select deployer ')
    deployments = {}
    data = {}
    with open(DEPLOYMENT_ARTIFACTS) as file:
        deployments = json.load(file)

    # Deploy USDs Contract
    print('\n -- Deploying USDs contract -- \n')
    proxy_admin, _ = deploy(deployments, ProxyAdmin, [{'from': owner}], 'proxy_admin')    
    usds = Contract.from_abi('USDs', deployments['usds'], USDs.abi)

    # Deploy Vault contract
    print('\n -- Deploying Vault -- \n')
    vault_impl, _ = deploy(deployments, VaultCore, [{'from': owner}], 'vault_impl')

    vault_proxy, new_vault = deploy(
        deployments,
        TUP,
        [vault_impl, proxy_admin, eth_utils.to_bytes(hexstr='0x'), {'from': owner}],
        'vault',
    )
    vault = Contract.from_abi('Vault', vault_proxy, VaultCore.abi)
    if new_vault:
        vault.initialize({'from': owner})

    # Deploy oracles
    print('\n -- Deploying and configuring Oracle contracts -- \n')
    master_price_oracle, new_master_oracle = deploy(
        deployments, MasterPriceOracle, [{'from': owner}], 'master_price_oracle'
    )

    # Deploy Vault plugins
    print('\n -- Deploying Vault Plugins -- \n')
    collateral_manager, new_collateral_manager = deploy(
        deployments, CollateralManager, [vault, {'from': owner}], 'collateral_manager'
    )
    fee_calculator, new_fee_calculator = deploy(
        deployments, FeeCalculator, [collateral_manager, {'from': owner}], 'fee_calculator'
    )
    dripper, new_dripper = deploy(
        deployments, Dripper, [vault, 7 * 86400, {'from': owner}], 'dripper'
    )
    
    rebase_manager, new_rebase_manager = deploy(
        deployments,
        RebaseManager,
        [vault, dripper, 86400, 1000, 300, {'from': owner}],
        'rebase_manager',
    )
    if(new_dripper and not new_rebase_manager):
        rebase_manager.updateDripper(dripper, {'from':owner})
    
    spa_buyback_impl, new_spa_buyback_impl = deploy(
        deployments, SPABuyback, [{'from': owner}], 'spa_buyback_impl'
    )
    spa_buyback_proxy, new_spa_buyback = deploy(
        deployments,
        TUP,
        [
            spa_buyback_impl,
            proxy_admin,
            eth_utils.to_bytes(hexstr='0x'),
            {'from': owner},
        ],
        'spa_buyback',
    )
    spa_buyback = Contract.from_abi('SPABuyback', spa_buyback_proxy, SPABuyback.abi)

    yield_reserve, new_yield_reserve = deploy(
        deployments,
        YieldReserve,
        [spa_buyback, vault, master_price_oracle, dripper, {'from': owner}],
        'yield_reserve',
    )

    print('Configuring yield reserve contract')
    yield_reserve.toggleSrcTokenPermission(usds, True, {'from': owner})
    yield_reserve.toggleDstTokenPermission(deployments['USDC'], True, {'from': owner})
    yield_reserve.toggleDstTokenPermission(deployments['USDCe'], True, {'from': owner})
    yield_reserve.toggleDstTokenPermission(deployments['DAI'], True, {'from': owner})
    yield_reserve.toggleDstTokenPermission(deployments['FRAX'], True, {'from': owner})
    yield_reserve.toggleDstTokenPermission(deployments['LUSD'], True, {'from': owner})

    # Configuring vault
    if(new_collateral_manager or new_vault):
        vault.updateCollateralManager(collateral_manager, {'from': owner})

    if(new_spa_buyback or new_vault):
        vault.updateFeeVault(spa_buyback, {'from': owner})

    if(new_master_oracle or new_vault):
        vault.updateOracle(master_price_oracle, {'from': owner})

    if(new_fee_calculator or new_vault):
        vault.updateFeeCalculator(fee_calculator, {'from': owner})

    if(new_rebase_manager or new_vault):
        vault.updateRebaseManager(rebase_manager, {'from': owner})

    if(new_yield_reserve or new_vault):
        vault.updateYieldReceiver(yield_reserve, {'from': owner})

    collateral_data = [
        CollateralData(
            deployments['USDC'],
            True,
            True,
            True,
            1,
            2,
            9700,
            2500,
        ),
        CollateralData(
            deployments['USDCe'],
            True,
            True,
            True,
            1,
            2,
            9700,
            2000,
        ),
        CollateralData(
            deployments['DAI'], True, True, True, 1, 2, 9700, 2000
        ),
        CollateralData(
            deployments['USDT'],
            True,
            True,
            True,
            1,
            2,
            9700,
            1500,
        ),
        CollateralData(
            deployments['FRAX'],
            True,
            True,
            True,
            10,
            1,
            9700,
            1000,
        ),
        CollateralData(
            deployments['LUSD'],
            True,
            True,
            True,
            50,
            1,
            9700,
            1000,
        ),
    ]

    print('Setting up collateral information:')
    if new_collateral_manager:
        for item in collateral_data:
            print(f'Adding collateral: {item.address}')
            collateral_manager.addCollateral(
                item.address,
                [
                    item.mint_allowed,
                    item.redeem_allowed,
                    item.allocation_allowed,
                    item.base_fee_in,
                    item.base_fee_out,
                    item.downside_peg,
                    item.desired_collateral_composition,
                ],
                {'from': owner},
            )

    # vault.transferOwnership(USDS_OWNER_ADDR, {'from': owner})
    # collateral_manager.transferOwnership(USDS_OWNER_ADDR, {'from': owner})
    # yield_reserve.transferOwnership(USDS_OWNER_ADDR, {'from': owner})
    # dripper.transferOwnership(USDS_OWNER_ADDR, {'from': owner})
    # rebase_manager.transferOwnership(USDS_OWNER_ADDR, {'from': owner})
        

    data = {
        **data,
        'proxy_admin': proxy_admin.address,
        'usds': usds.address,
        'master_price_oracle': master_price_oracle.address,
        'vault': vault.address,
        'vault_impl': vault_impl.address,
        'fee_calculator': fee_calculator.address,
        'collateral_manager': collateral_manager.address,
        'dripper': dripper.address,
        'rebase_manager': rebase_manager.address,
        'spa_buyback_impl': spa_buyback_impl.address,
        'spa_buyback': spa_buyback.address,
        'yield_reserve': yield_reserve.address,
    }

    deployments = {**deployments, **data}
    with open(DEPLOYMENT_ARTIFACTS, 'w') as outfile:
        json.dump(deployments, outfile)