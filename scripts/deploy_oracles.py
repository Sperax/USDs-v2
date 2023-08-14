from brownie import VSTOracle, MasterPriceOracle, ChainlinkOracle, SPAOracle, USDsOracle

from .configurations import (
    USDS_OWNER_ADDR,
    SPA,
    USDS,
    USDC_E,
    USDT,
    FRAX,
    DAI,
    LUSD,
    VST,
)

from .utils import get_user


def main():
    user = get_user("Import user: ")

    chainlink_feeds = [
        [USDC_E, ["0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3", 1e8]],  # USDC.e
        [DAI, ["0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB", 1e8]],  # DAI
        [FRAX, ["0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8", 1e8]],  # FRAX
        [USDT, ["0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7", 1e8]],  # USDT
        [LUSD, ["0x0411D28c94d85A36bC72Cb0f875dfA8371D8fFfF", 1e8]],  # LUSD
    ]

    chainlink_oracle = ChainlinkOracle.deploy(
        chainlink_feeds, {"from": user}, publish_source=True
    )
    vst_oracle = VSTOracle.deploy({"from": user}, publish_source=True)
    master_price_oracle = MasterPriceOracle.deploy({"from": user}, publish_source=True)

    master_price_oracle.updateTokenPriceFeed(
        USDC_E, chainlink_oracle, chainlink_oracle.getTokenPrice.encode_input(USDC_E)
    )
    master_price_oracle.updateTokenPriceFeed(
        DAI, chainlink_oracle, chainlink_oracle.getTokenPrice.encode_input(DAI)
    )
    master_price_oracle.updateTokenPriceFeed(
        FRAX, chainlink_oracle, chainlink_oracle.getTokenPrice.encode_input(FRAX)
    )
    master_price_oracle.updateTokenPriceFeed(
        USDT, chainlink_oracle, chainlink_oracle.getTokenPrice.encode_input(USDT)
    )
    master_price_oracle.updateTokenPriceFeed(
        LUSD, chainlink_oracle, chainlink_oracle.getTokenPrice.encode_input(LUSD)
    )
    master_price_oracle.updateTokenPriceFeed(
        VST, vst_oracle, vst_oracle.getPrice.encode_input()
    )

    spa_oracle = SPAOracle.deploy(
        master_price_oracle, USDC_E, 10000, 600, 70, {"from": user}, publish_source=True
    )

    usds_oracle = USDsOracle.deploy(
        master_price_oracle, USDC_E, 500, 600, {"from": user}, publish_source=True
    )

    master_price_oracle.updateTokenPriceFeed(
        SPA, spa_oracle, spa_oracle.getPrice.encode_input()
    )
    master_price_oracle.updateTokenPriceFeed(
        USDS, usds_oracle, usds_oracle.getPrice.encode_input()
    )

    chainlink_oracle.transferOwnership(USDS_OWNER_ADDR, {"from": user})
    spa_oracle.transferOwnership(USDS_OWNER_ADDR, {"from": user})
    usds_oracle.transferOwnership(USDS_OWNER_ADDR, {"from": user})
    master_price_oracle.transferOwnership(USDS_OWNER_ADDR, {"from": user})

    tokens = [SPA, USDS, USDC_E, USDT, FRAX, DAI, VST, LUSD]
    for token in tokens:
        print(f"Fetching Price feed for {token}: {master_price_oracle.getPrice(token)}")
