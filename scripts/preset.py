from brownie import (
    ERC20,
    interface,
    MasterPriceOracle,
    ChainlinkOracle,
    AaveStrategy,
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
USDs_OWNER = '0x5b12d9846F8612E439730d18E1C12634753B1bF1'

def main():
    owner = get_user('Select deployer ')
    data = {}
    with open(DEPLOYMENT_ARTIFACTS) as file:
        data = json.load(file)

    # Deploy all the ERC20 contracts
    usdc = ERC20.at(data['USDC'])
    usdc_e = ERC20.at(data['USDCe'])
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
    aave_strategy = Contract.from_abi(
        'AaveStrategy', data['aave_strategy'], AaveStrategy.abi
    )
    # stargate_strategy = Contract.from_abi(
    #     'StargateStrategy', data['stargate_strategy', StargateStrategy.abi]
    # )
    # compound_strategy = Contract.from_abi(
    #     'CompoundStrategy', data['compound_strategy', CompoundStrategy]
    # )

    if (MIGRATE):
        print('Add collateral Strategies')
        # @note add USDT to aave strategy
        collateral_manager.addCollateralStrategy(usdc, aave_strategy, 5000, {'from': owner})
        collateral_manager.addCollateralStrategy(lusd, aave_strategy, 5000, {'from': owner})
        collateral_manager.addCollateralStrategy(usdc_e, aave_strategy, 5000, {'from': owner})
        collateral_manager.addCollateralStrategy(dai, aave_strategy, 5000, {'from': owner})
        
        # Old addresses
        old_vault_addr = '0xF783DD830A4650D2A8594423F123250652340E3f'
        old_vault_impl = '0xEC399A159cc60bCEd415A58f50B138E5D0bB6f89'
        old_aave_impl = '0xB172d61f8682b977Cf0888ce9337C41B50f94910'
        # stargate_strategy = Contract.from_abi('old_aave_strategy', '0xF30Db0F56674b51050630e53043c403f8E162Bf2', S.abi)
        pa_owner = proxy_admin.owner()

        # GnosisTxn  # Upgrade old vault for migration
        print('Upgrade essential old contracts')
        old_aave_strategy = Contract.from_abi('old_aave_strategy', '0xBC683Dee915313b01dEff10D29342E59e1d75C09', interface.IOldAaveStrategy.abi)
        proxy_admin.upgrade(old_vault_addr, old_vault_impl, {'from': pa_owner})
        proxy_admin.upgrade(old_aave_strategy, old_aave_impl, {'from': pa_owner})
        old_vault = Contract.from_abi('old_vault', old_vault_addr, interface.IOldVault.abi)

        # Transfer any collected yield to yield_reserve
        print('Harvest Yield from old strategies')
        old_vault.updateBuybackAddr(yield_reserve, {'from': USDs_OWNER})
        old_vault.harvestInterest(old_aave_strategy, usdc_e, {'from': USDs_OWNER})
        old_vault.harvestInterest(old_aave_strategy, lusd, {'from': USDs_OWNER})
        old_vault.harvestInterest(old_aave_strategy, dai, {'from': USDs_OWNER})

        # Migrate the funds
        print('Withdraw funds to vault from old strategy')
        old_aave_strategy.withdrawToVault(usdc, old_aave_strategy.checkBalance(usdc), {'from': USDs_OWNER})
        old_aave_strategy.withdrawToVault(dai, old_aave_strategy.checkBalance(dai), {'from': USDs_OWNER})
        old_aave_strategy.withdrawToVault(usdc_e, old_aave_strategy.checkBalance(usdc_e), {'from': USDs_OWNER})
        old_aave_strategy.withdrawToVault(lusd, old_aave_strategy.checkAvailableBalance(lusd), {'from': USDs_OWNER})

        print('Rescue LUSD')
        # https://github.com/bgd-labs/aave-address-book/blob/main/src/AaveV3Arbitrum.sol
        aLusd = ERC20.at('0x8ffDf2DE812095b1D19CB146E4c004587C0A0692')
        old_aave_strategy.withdrawLPForMigration(lusd, 2**256 - 1, {'from': USDs_OWNER})
        aLusd.approve(aave_strategy, 1e24, {'from': USDs_OWNER})
        aave_strategy.depositLp(lusd, aLusd.balanceOf(USDs_OWNER), {'from': USDs_OWNER})

        print("Migrate funds from old vault")
        old_vault.migrateFunds([usdc, dai, lusd, usdc_e, frax], vault, {'from': USDs_OWNER})

        # Auto yield-reserve 
        print("Bootstrap dripper with yield reserve")
        old_vault.migrateFunds([usds], USDs_OWNER, {'from': USDs_OWNER})
        usds.approve(dripper, usds.balanceOf(USDs_OWNER), {'from': USDs_OWNER})
        dripper.addUSDs(usds.balanceOf(USDs_OWNER), {'from': USDs_OWNER})

        # GnosisTxn # Upgrade the USDs contract 
        print("upgrade the new contracts and connect vault")
        proxy_admin.upgrade(usds, data['usds_impl'], {'from': pa_owner})
        usds.updateVault(vault, {'from': usds.owner()})

        fee_calculator.calibrateFeeForAll({'from': owner})