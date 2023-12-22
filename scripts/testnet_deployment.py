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
    MockStrategy,
    ProxyAdmin,
    TUP,
    Contract,
    network,
)

import json

from .utils import get_user
import eth_utils

DEPLOYMENT_ARTIFACTS = f'deployed/{network.show_active()}/deployment_data.json'


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


tokens = {
    'usdc': Token('USDC', 'USDC', 6),
    'dai': Token('Dai', 'DAI', 18),
    'usdt': Token('Tether', 'USDT', 6),
    'arb': Token('ARB', 'ARB', 18),
    'spa': Token('Sperax', 'SPA', 18),
    'frax': Token('Frax', 'FRAX', 18),
    'lusd': Token('lUsd', 'LUSD', 18)
}


def deploy(deployments, contract, args, key):
    if key in deployments.keys():
        print(f'\n Using pre-deployed {key}\n')
        return contract.at(deployments[key]), False
    else:
        return contract.deploy(*args), True


def main():
    owner = get_user('Select deployer ')
    deployments = {}
    data = {}
    with open(DEPLOYMENT_ARTIFACTS) as file:
        deployments = json.load(file)

    # Deploy all the ERC20 contracts
    print('\n -- Deploying ERC20 contracts -- \n')
    for tkn in tokens.keys():
        token = tokens[tkn]
        print(f'\n -Deploying {token.symbol}')
        tkn_contract, _ = deploy(
            deployments,
            CustomERC20,
            [token.name, token.symbol, token.decimals, {'from': owner}],
            token.symbol,
        )
        vars()[token.symbol] = tkn_contract
        data[token.symbol] = tkn_contract.address

    # Deploy USDs Contract
    print('\n -- Deploying USDs contract -- \n')
    usds_impl, new_usds_impl = deploy(deployments, USDs, [{'from': owner}], 'usds_impl')
    proxy_admin, _ = deploy(deployments, ProxyAdmin, [{'from': owner}], 'proxy_admin')
    usds_proxy, new_deployment = deploy(
        deployments,
        TUP,
        [usds_impl, proxy_admin, eth_utils.to_bytes(hexstr='0x'), {'from': owner}],
        'usds',
    )
    usds = Contract.from_abi('USDs', usds_proxy, USDs.abi)

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
    
    if new_deployment:
        usds.initialize('Sperax USD', 'USDs', vault, {'from': owner})
    elif new_usds_impl:
        proxy_admin.upgrade(usds_proxy, usds_impl, {'from': owner})

    # Deploy oracles
    print('\n -- Deploying and configuring Oracle contracts -- \n')
    # Chainlink price feed for arbitrum-sepolia
    # https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum&page=1#arbitrum-sepolia
    chainlink_feeds = [
        [
            data['USDC'],
            ['0x0153002d20B96532C639313c2d54c3dA09109309', 86400, 1e8],
        ],  # USDC
        [
            data['DAI'],
            ['0xb113F5A928BCfF189C998ab20d753a47F9dE5A61', 86400, 1e8],
        ],  # DAI
        [
            data['USDT'],
            ['0x80EDee6f667eCc9f63a0a6f55578F870651f06A4', 86400, 1e8],
        ],  # USDT
        [
            data['ARB'],
            ['0xD1092a65338d049DB68D7Be6bD89d17a0929945e', 86400, 1e8],
        ],  # ARB
        
    ]
    chainlink_oracle, _ = deploy(
        deployments,
        ChainlinkOracle,
        [chainlink_feeds, {'from': owner}],
        'chainlink_oracle',
    )

    master_price_oracle, new_master_oracle = deploy(
        deployments, MasterPriceOracle, [{'from': owner}], 'master_price_oracle'
    )

    dia_oracle, _ = deploy(
        deployments,
        DIAOracle,
        [
            [
                [data['SPA'], 'SPA/USD'],
                [usds, 'USDS/USD'],
            ],
            {'from': owner},
        ],
        'dia_oracle',
    )

    # Configuring oracles
    master_price_oracle.updateTokenPriceFeed(
        data['USDC'],
        chainlink_oracle,
        chainlink_oracle.getTokenPrice.encode_input(data['USDC']),
        {'from': owner},
    )

    master_price_oracle.updateTokenPriceFeed(
        data['DAI'],
        chainlink_oracle,
        chainlink_oracle.getTokenPrice.encode_input(data['DAI']),
        {'from': owner},
    )

    master_price_oracle.updateTokenPriceFeed(
        data['USDT'],
        chainlink_oracle,
        chainlink_oracle.getTokenPrice.encode_input(data['USDT']),
        {'from': owner},
    )

    # master_price_oracle.updateTokenPriceFeed(
    #     data['SPA'],
    #     dia_oracle,
    #     dia_oracle.getPrice.encode_input(data['SPA']),
    #     {'from': owner},
    # )

    # master_price_oracle.updateTokenPriceFeed(
    #     usds, dia_oracle, dia_oracle.getPrice.encode_input(usds), {'from': owner}
    # )

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
        [vault, dripper, 86400, 1000, 800, {'from': owner}],
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
    if new_spa_buyback:
        spa_buyback.initialize(owner, 5000, {'from': owner})
        spa_buyback.updateOracle(master_price_oracle, {'from': owner})

    elif new_spa_buyback_impl:
        proxy_admin.upgrade(spa_buyback, spa_buyback_impl, {'from': owner})

    yield_reserve, new_yield_reserve = deploy(
        deployments,
        YieldReserve,
        [spa_buyback, vault, master_price_oracle, dripper, {'from': owner}],
        'yield_reserve',
    )

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
    if(new_vault):
        usds.updateVault(vault, {'from': owner})

    print('\n -- Deploying MockStrategy -- \n')
    strategy_impl, _ = deploy(deployments, MockStrategy, [{'from': owner}], 'strategy_impl')

    strategy_proxy, new_strategy = deploy(
        deployments,
        TUP,
        [strategy_impl, proxy_admin, eth_utils.to_bytes(hexstr='0x'), {'from': owner}],
        'mock_strategy',
    )
    strategy = Contract.from_abi('MockStrategy', strategy_proxy, MockStrategy.abi)
    if new_strategy:
        strategy.initialize(
            vault, 
            [data['USDC'], data['DAI'], data['USDT']],
            [1e3, 1e15, 1e3],
            data['ARB'],
            1e15,
            {'from': owner}
        )

    collateral_data = [
        CollateralData(
            data['USDC'],
            True,
            True,
            True,
            20,
            20,
            9800,
            2500,
        ),
        CollateralData(
            data['DAI'], True, True, True, 20, 20, 9800, 2500
        ),
        CollateralData(
            data['USDT'],
            True,
            True,
            True,
            20,
            20,
            9800,
            2500,
        ),
    ]

    print('Setting up collateral information:')
    if new_collateral_manager:
        for item in collateral_data:
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
            collateral_manager.addCollateralStrategy(item.address, strategy, 5000, {'from': owner})

    data = {
        **data,
        'proxy_admin': proxy_admin.address,
        'usds': usds.address,
        'usds_impl': usds_impl.address,
        'chainlink_oracle': chainlink_oracle.address,
        'master_price_oracle': master_price_oracle.address,
        'dia_oracle': dia_oracle.address,
        'vault': vault.address,
        'vault_impl': vault_impl.address,
        'fee_calculator': fee_calculator.address,
        'collateral_manager': collateral_manager.address,
        'dripper': dripper.address,
        'rebase_manager': rebase_manager.address,
        'spa_buyback_impl': spa_buyback_impl.address,
        'spa_buyback': spa_buyback.address,
        'yield_reserve': yield_reserve.address,
        'mock_strategy': strategy.address
    }

    deployments = {**deployments, **data}
    with open(DEPLOYMENT_ARTIFACTS, 'w') as outfile:
        json.dump(deployments, outfile)