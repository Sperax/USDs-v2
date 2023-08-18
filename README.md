
<p align="center" style="font-size:50px"> <img src="./docs/Logo.png" width="50" align="center"> </t> <u>Sperax USDs Protocol</u> <img src="./docs/Logo.png" width="50" align="center"> </p>

## Description:
This repository contains the smart contracts and configurations for USDs protocol.
The project uses foundry framework for compiling, developing and testing contracts and brownie for deployments and scripting.

## Project Summary:

* [Summary](/docs/src/SUMMARY.md)

## Project Setup:
* [Install Foundry](https://book.getfoundry.sh/getting-started/installation)
* [Install Brownie](https://eth-brownie.readthedocs.io/en/stable/install.html)
* Run command ```$ npm ci```

## Project interaction:

Below are some npm scripts for interacting with the project
``` json
"scripts": {
    "test": "forge test -vvv",
    "test-contract": "forge test -vvv --match-contract",
    "test-file": "forge test -vvv --match-path",
    "test-function": "forge test -vvv --match-test",
    "install-pip-packages": "pip install -r pip-requirements.txt",
    "install-husky": "husky install",
    "prepare": "npm-run-all install-husky install-pip-packages",
    "slither-analyze": "slither .",
    "lint:fix": "prettier --write 'scripts/**/*.{js,ts}' 'test/**/*.{js,ts}' '*.{js,ts}' && tslint --fix --config tslint.json --project tsconfig.json",
    "forge-coverage": "forge coverage --report lcov && rm -rf ./coverage && genhtml lcov.info --output-dir coverage && mv lcov.info ./coverage",
    "lint-contract": "solhint 'docs/src/contracts/**/*.sol' 'test/**/*.sol' -f table",
    "lint-contract:fix": "prettier --write 'docs/src/contracts/**/*.sol' 'test/**/*.sol'"
  }
```