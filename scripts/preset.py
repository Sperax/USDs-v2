from brownie import (
    ERC20,
    MasterPriceOracle,
    ChainlinkOracle,
    AaveStrategy,
    StargateStrategy,
    CompoundStrategy,
    USDs,
    VaultCore,
    CollateralManager,
    FeeCalculator,
    Dripper,
    RebaseManager,
    SPABuyback,
    YieldReserve,
    ProxyAdmin,
    TUP as TransparentUpgradeableProxy,
    FluidStrategy,
    Contract,
    network,
)

import json

from .utils import (
    get_user,
    get_config,
    Deployment_data,
    confirm,
    get_tx_info,
    run_step
)
from .configurations import deployment_config
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
    stargate_strategy = Contract.from_abi(
        'StargateStrategy', data['stargate_strategy'], StargateStrategy.abi
    )
    compound_strategy = Contract.from_abi(
        'CompoundStrategy', data['compound_strategy'], CompoundStrategy.abi
    )
    fluid_strategy = Contract.from_abi(
        'FluidStrategy', deployFluidStrategy(deployment_config, owner), FluidStrategy.abi
    )
    
    # Fluid strategy simulations
    # USDT
    collateralStrategies = collateral_manager.getCollateralStrategies(usdt)
    collateralAmounts = []
    collateralAmounts.append(collateral_manager.getCollateralInVault(usdt))
    for collateralStrategy in collateralStrategies:
        collateralAmounts.append(collateral_manager.getCollateralInAStrategy(usdt, collateralStrategy))
    totalCollateralUSDT = sum(collateralAmounts)
    collateralPerStrategy = totalCollateralUSDT/3
    i = 1
    for collateralStrategy in collateralStrategies:
        if (collateralAmounts[i] > collateralPerStrategy):
            amountToWithdraw = collateralAmounts[i] - collateralPerStrategy
            collateralStrategy = Contract.from_abi('Strategy', collateralStrategy, AaveStrategy.abi)
            collateralStrategy.withdrawToVault(usdt, amountToWithdraw, ({'from': USDs_OWNER}))
        collateral_manager.updateCollateralStrategy(usdt, collateralStrategy, 3333, {'from': USDs_OWNER})
        i+=1
    collateral_manager.updateCollateralStrategy(usdt, fluid_strategy, 3333, {'from': USDs_OWNER})
    print('Configuring collateral strategies')

def deployFluidStrategy(configuration, deployer):
    config_name, config_data = get_config("Select config for deployment", configuration)
    contract = config_data.contract
    config = config_data.config
    deployment_data = {}
    deployed_contract = None
    tx_list = []
    print(json.dumps(config, default=lambda o: o.__dict__, indent=2))
    confirm("Are the above configurations correct?")

    print("\nDeploying implementation contract")
    impl = contract.deploy({"from": deployer})
    tx_list.append(get_tx_info("Implementation_deployment", impl.tx))

    proxy_admin = config.proxy_admin

    if proxy_admin is None:
        print("\nDeploying proxy admin contract")
        pa_deployment = ProxyAdmin.deploy({"from": deployer})
        tx_list.append(get_tx_info("Proxy_admin_deployment", pa_deployment.tx))
        proxy_admin = pa_deployment.address

    print("\nDeploying proxy contract")
    proxy = TransparentUpgradeableProxy.deploy(
        impl.address,
        proxy_admin,
        eth_utils.to_bytes(hexstr="0x"),
        {"from": deployer},
    )
    tx_list.append(get_tx_info("Proxy_deployment", proxy.tx))

    # Load the deployed contracts
    deployed_contract = Contract.from_abi(config_name, proxy.address, contract.abi)

    print("\nInitializing proxy contract")
    init = deployed_contract.initialize(
        *config.deployment_params.values(), {"from": deployer}
    )

    tx_list.append(get_tx_info("Proxy_initialization", init))

    for step in config.post_deployment_steps:
        step, _, tx = run_step(step, deployed_contract, deployer)
        if tx is not None:
            tx_list.append(get_tx_info("Post_deployment_step", tx))

    deployment_data["proxy_addr"] = proxy.address
    deployment_data["impl_addr"] = impl.address
    deployment_data["proxy_admin"] = proxy_admin
    return proxy.address
