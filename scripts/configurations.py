from brownie import (
    VaultCore,
    USDs
)

from .utils import (
    Deployment_data,
    Step,
    Deployment_config,
    Upgrade_config,
    Upgrade_data
)

PROXY_ADMIN = '0x3E49925A79CbFb68BAa5bc9DFb4f7D955D1ddF25'
USDS_ADDR = '0xD74f5255D557944cf7Dd0E45FF521520002D5748'
USDS_OWNER_ADDR = '0x5b12d9846F8612E439730d18E1C12634753B1bF1'

deployment_config = {
    'vault': Deployment_data(
        contract=VaultCore,
        config=Deployment_config(
            upgradeable=True,
            proxy_admin= PROXY_ADMIN,
            deployment_params={},
            post_deployment_steps=[
                Step(
                    func='transferAdminRole',
                    args={
                        'new_admin': USDS_OWNER_ADDR
                             
                    },
                    transact=True,
                )
            ]
        )
    )
}

upgrade_config = {
    'usds_v9': Upgrade_data(
        contract=USDs,
        config=Upgrade_config(
            gnosis_upgrade=True,
            proxy_address=USDS_ADDR,
            proxy_admin=PROXY_ADMIN
        ),
        description="Remove upgrade account functionality"
    ) 
}