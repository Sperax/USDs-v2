import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-solhint";
import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    hardhat: {
      forking: {
        url: "",
        // blocknumber: <blk_no_for_fork>
      },
    },
  },
};

export default config;
