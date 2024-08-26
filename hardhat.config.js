require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      blockGasLimit: 12500000,
      allowUnlimitedContractSize: true,
    },
    reporter: {
      gas: 5000000,
      url: "http://localhost:8545",
    },
    coverage: {
      url: "http://localhost:8555",
    },
  },
  etherscan: {
    // The url for the Etherscan API you want to use.
    // For example, here we're using the one for the Ropsten test network
    //url: "https://api-rinkeby.etherscan.io/api",
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true, // Default: false
        runs: 200, // Default: 200
      },
      viaIR: true,
    }
  },
  gasReporter: {
    currency: "USD",
    coinmarketcap: process.env.COINMARKETCAP_KEY,
    enabled: process.env.REPORT_GAS ? true : false,
  },
};
