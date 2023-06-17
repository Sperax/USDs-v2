import "@foundry-rs/hardhat-forge";
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-solhint";
import "@openzeppelin/hardhat-upgrades";
import { config as dotenvConf } from "dotenv";
import { task } from "hardhat/config";
import type { HardhatUserConfig, HttpNetworkUserConfig } from "hardhat/types";

dotenvConf({ path: __dirname + "/.env" });

const { ALCHEMY_KEY, PK, MNEMONIC } = process.env;

const DEFAULT_MNEMONIC = "hardhat";

const sharedNetworkConfig: HttpNetworkUserConfig = {};
if (PK) {
  sharedNetworkConfig.accounts = [PK];
} else {
  sharedNetworkConfig.accounts = {
    mnemonic: MNEMONIC || DEFAULT_MNEMONIC,
  };
}

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.16",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    "arbitrum-main": {
      url: `https://arb-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`,
      ...sharedNetworkConfig,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    hardhat: {
      forking: {
        url: `https://arb-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`,
        blockNumber: 93644011,
      },
    },
  },
};

export default config;
