from brownie import (
    SPABuyback,
    VaultCore,
    AaveStrategy,
    StargateStrategy,
    CompoundStrategy,
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
VAULT = "0x6Bbc476Ee35CBA9e9c3A59fc5b10d7a0BC6f74Ca"

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
    "aaveStrategy": Deployment_data(
        # @note https://github.com/bgd-labs/aave-address-book/blob/main/src/AaveV3Arbitrum.sol  # noqa
        contract=AaveStrategy,
        config=Deployment_config(
            upgradeable=True,
            proxy_admin=PROXY_ADMIN,
            deployment_params={
                'platform_addr': '0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb',
                'vault': VAULT
            },
            post_deployment_steps=[
                Step(
                    func="setPTokenAddress",
                    args={"asset": USDC, "lpToken": "0x724dc807b04555b71ed48a6896b6F41593b8C637"},
                    transact=True,
                ),
                Step(
                    func="setPTokenAddress",
                    args={"asset": DAI, "lpToken": "0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE"},
                    transact=True,
                ),
                Step(
                    func="setPTokenAddress",
                    args={"asset": USDC_E, "lpToken": "0x625E7708f30cA75bfd92586e17077590C60eb4cD"},
                    transact=True,
                ),
                Step(
                    func="setPTokenAddress",
                    args={"asset": LUSD, "lpToken": "0x8ffDf2DE812095b1D19CB146E4c004587C0A0692"},
                    transact=True,
                ),
                Step(
                    func="transferOwnership",
                    args={"new_admin": USDS_OWNER_ADDR},
                    transact=True,
                )
            ]
        )
    ),
    "stargateStrategy": Deployment_data(
        # @note https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet#arbitrum
        contract=StargateStrategy,
        config=Deployment_config(
            upgradeable=True,
            proxy_admin=PROXY_ADMIN,
            deployment_params={
                'router': '0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614',
                'vault': VAULT,
                'eToken': '0x912CE59144191C1204E64559FE8253a0e49E6548',
                'farm': '0x9774558534036Ff2E236331546691b4eB70594b1',
                'depositSlippage': 50,
                'withdrawSlippage': 50
            },
            post_deployment_steps=[
                Step(
                    func="setPTokenAddress",
                    args={
                        "asset": USDC_E,
                        "lpToken": "0x892785f33CdeE22A30AEF750F285E18c18040c3e",
                        "pid": 1,
                        "rewardPid": 0
                    },
                    transact=True,
                ),
                Step(
                    func="setPTokenAddress",
                    args={
                        "asset": USDT,
                        "lpToken": "0xB6CfcF89a7B22988bfC96632aC2A9D6daB60d641",
                        "pid": 2,
                        "rewardPid": 1
                    },
                    transact=True,
                ),
                Step(
                    func="setPTokenAddress",
                    args={
                        "asset": FRAX,
                        "lpToken": "0xaa4BF442F024820B2C28Cd0FD72b82c63e66F56C",
                        "pid": 7,
                        "rewardPid": 3
                    },
                    transact=True,
                ),
                Step(
                    func="transferOwnership",
                    args={"new_admin": USDS_OWNER_ADDR},
                    transact=True,
                )
                
            ]
            
        )
    ),
    "compoundStrategy": Deployment_data(
        # @note https://docs.compound.finance/#networks
        contract=CompoundStrategy,
        config=Deployment_config(
            upgradeable=True,
            proxy_admin=PROXY_ADMIN,
            deployment_params={
                'vault': VAULT,
                'rewardPool': '0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae',
            },
            post_deployment_steps=[
                Step(
                    func="setPTokenAddress",
                    args={
                        "asset": USDC,
                        "lpToken": "0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf",
                    },
                    transact=True,
                ),
                Step(
                    func="setPTokenAddress",
                    args={
                        "asset": USDC_E,
                        "lpToken": "0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA",
                    },
                    transact=True,
                ),
                Step(
                    func="transferOwnership",
                    args={"new_admin": USDS_OWNER_ADDR},
                    transact=True,
                )
            ]
        )
    )
    
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
