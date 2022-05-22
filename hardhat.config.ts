import * as dotenv from "dotenv";

import { HardhatUserConfig } from "hardhat/config";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
require("hardhat-contract-sizer");

dotenv.config();

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.7",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {},
        rinkeby: {
            url: process.env.RINKEBY_RPC_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            },
            saveDeployments: true,
        },
        polygon: {
            url: process.env.POLYGON_RPC_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            },
            saveDeployments: true,
        },
        mumbai: {
            url: process.env.MUMBAI_RPC_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            },
            saveDeployments: true,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0,
        },
        competitionCreator: {
            default: 1,
        },
    },
    gasReporter: {
        enabled: process.env.REPORT_GAS !== undefined,
        currency: "USD",
    },
    etherscan: {
        apiKey: {
            rinkeby: process.env.ETHERSCAN_API_KEY,
            polygon: process.env.POLYGONSCAN_API_KEY,
            polygonMumbai: process.env.POLYGONSCAN_API_KEY,
        },
    },
};

export default config;
