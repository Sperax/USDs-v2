from brownie import (
    Contract,
    network,
    PA as ProxyAdmin,
    TUP as TransparentUpgradeableProxy,
    accounts,
)
from .configurations import deployment_config, upgrade_config
from .utils import (
    Deployment_data,
    Upgrade_data,
    get_config,
    print_dict,
    _getYorN,
    confirm,
    save_deployment_artifacts,
    run_step,
    get_tx_info,
    get_user,
)
import eth_utils
import click
import json

# from brownie.network import gas_price
# from brownie.network.gas.strategies import ExponentialScalingStrategy

# gas_strategy = ExponentialScalingStrategy('0.1 gwei', '0.2 gwei')
# gas_price(gas_strategy)


def deploy(configuration, deployer):
    """Utility to deploy contracts

    Args:
        configuration (Deployment_data{}): Configuration data for deployment
        deployer (address): address of the deployer

    Returns:
        dict: deployment_data
    """
    config_name, config_data = get_config("Select config for deployment", configuration)
    if type(config_data) is not Deployment_data:
        print("Incorrect configuration data")
        return
    contract = config_data.contract
    config = config_data.config
    deployment_data = {}
    deployed_contract = None
    tx_list = []
    print(json.dumps(config, default=lambda o: o.__dict__, indent=2))
    confirm("Are the above configurations correct?")

    if config.upgradeable:
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

        deployment_data["proxy_addr"] = proxy.address
        deployment_data["impl_addr"] = impl.address
        deployment_data["proxy_admin"] = proxy_admin

    else:
        print(f"\nDeploying {config_name} contract")
        deployed_contract = contract.deploy(
            *config.deployment_params.values(), {"from": deployer}
        )
        tx_list.append(get_tx_info("Deployment_transaction", deployed_contract.tx))

        deployment_data["contract_addr"] = deployed_contract.address

    for step in config.post_deployment_steps:
        step, _, tx = run_step(step, deployed_contract, deployer)
        if tx is not None:
            tx_list.append(get_tx_info("Post_deployment_step", tx))

    print_dict("Printing deployment data", deployment_data, 20)
    deployment_data["type"] = "Deployment"
    deployment_data["transactions"] = tx_list
    deployment_data["config_name"] = config_name
    deployment_data["config"] = config
    save_deployment_artifacts(deployment_data, config_name, "Deployment")


def upgrade(configuration, deployer):
    """Utility to upgrade a contract

    Args:
        configuration (_type_): Upgrade configuration list
        deployer (address): Address of the deployer

    Returns:
        _type_: _description_
    """
    config_name, config_data = get_config("Select config for upgrade", configuration)
    if type(config_data) is not Upgrade_data:
        print("Incorrect configuration data")
        return
    contract = config_data.contract
    config = config_data.config
    upgrade_data = {}
    tx_list = []

    print(json.dumps(config, default=lambda o: o.__dict__, indent=2))
    confirm("Are the above configurations correct?")

    print("\nDeploying new implementation contract")
    new_impl = contract.deploy({"from": deployer})
    tx_list.append(get_tx_info("New_implementation_deployment", new_impl.tx))
    if not config.gnosis_upgrade:
        admin = deployer
        flag = _getYorN("Is admin same as deployer?")
        if flag == "n":
            admin = get_user("Admin account: ")
        proxy_admin = Contract.from_abi("PA", config.proxy_admin, ProxyAdmin.abi)
        print("\nPerforming upgrade!")
        upgrade_tx = proxy_admin.upgrade(
            config.proxy_address, new_impl.address, {"from": admin}
        )
        tx_list.append(get_tx_info("Upgrade_transaction", upgrade_tx))
        deployed_contract = Contract.from_abi(
            config_name, config.proxy_address, contract.abi
        )
        for step in config.post_upgrade_steps:
            step, _, tx = run_step(step, deployed_contract, deployer)  # noqa
            if tx is not None:
                tx_list.append(get_tx_info("Post_upgrade_transaction", tx))
    else:
        print("\nPlease switch to Gnosis to perform upgrade!\n")

    upgrade_data["new_impl"] = new_impl.address
    print_dict("Printing Upgrade data", upgrade_data, 20)
    upgrade_data["Description"] = config_data.description
    upgrade_data["type"] = "Upgrade"
    upgrade_data["transactions"] = tx_list
    upgrade_data["config_name"] = config_name
    upgrade_data["config"] = config
    save_deployment_artifacts(upgrade_data, config_name, "Upgrade")
    return upgrade_data


def main():
    deployer = get_user("Deployer account: ")
    data = None
    menu = "\nPlease select one of the following options: \n"
    menu += "1. Deploy contract \n"
    menu += "2. Upgrade contract \n"
    menu += "3. Exit \n"
    menu += "-> "
    while True:
        choice = input(menu)
        if choice == "1":
            data = deploy(deployment_config, deployer)  # noqa
        elif choice == "2":
            data = upgrade(upgrade_config, deployer)  # noqa
        elif choice == "3":
            break
        else:
            print("Please select a valid option")
