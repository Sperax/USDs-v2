from brownie import (
    SPABuyback,
    VaultCore,
    USDs,
)

from .utils import (
    Deployment_data,
    Step,
    Deployment_config,
    Upgrade_config,
    Upgrade_data,
)

PROXY_ADMIN = "0x3E49925A79CbFb68BAa5bc9DFb4f7D955D1ddF25"
USDS_ADDR = "0xD74f5255D557944cf7Dd0E45FF521520002D5748"
SPA_BUYBACK_ADDR = "0xFbc0d3cA777722d234FE01dba94DeDeDb277AFe3"
USDS_OWNER_ADDR = "0x5b12d9846F8612E439730d18E1C12634753B1bF1"

## Tokens:
SPA = "0x5575552988A3A80504bBaeB1311674fCFd40aD4B"
USDS = "0xD74f5255D557944cf7Dd0E45FF521520002D5748"
USDC = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
USDC_E = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"
DAI = "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1"
FRAX = "0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F"
USDT = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"
LUSD = "0x93b346b6bc2548da6a1e7d98e9a421b42541425b"
ARB = "0x912CE59144191C1204E64559FE8253a0e49E6548"


deployment_config = {
    "vault": Deployment_data(
        contract=VaultCore,
        config=Deployment_config(
            upgradeable=True,
            proxy_admin=PROXY_ADMIN,
            deployment_params={},
            post_deployment_steps=[
                Step(
                    func="transferAdminRole",
                    args={"new_admin": USDS_OWNER_ADDR},
                    transact=True,
                )
            ],
        ),
    ),
}

upgrade_config = {
    "usds_v9": Upgrade_data(
        contract=USDs,
        config=Upgrade_config(
            gnosis_upgrade=True, proxy_address=USDS_ADDR, proxy_admin=PROXY_ADMIN
        ),
        description="Remove upgrade account functionality",
    ),
    "spa_buyback_v3": Upgrade_data(
        contract=SPABuyback,
        config=Upgrade_config(
            gnosis_upgrade=True, proxy_address=SPA_BUYBACK_ADDR, proxy_admin=PROXY_ADMIN
        ),
        description="1. Upgrade solc version  \n2. Add new veSPA rewarder and integrate new oracle",
    ),
}
