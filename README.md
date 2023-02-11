# YieldFolio

## Installation and Setup

1. [Install Brownie](https://eth-brownie.readthedocs.io/en/stable/install.html) & [Ganache](https://github.com/trufflesuite/ganache), if you haven't already. Make sure that the version of Ganache that you install is compatible with Brownie. You can check Brownie's Ganache dependency [here](https://eth-brownie.readthedocs.io/en/stable/install.html#dependencies).

2. Sign up for [Infura](https://infura.io/) and generate an API key. Store it in the `WEB3_INFURA_PROJECT_ID` environment variable.

```bash
export WEB3_INFURA_PROJECT_ID=YourProjectID
```

3. Sign up for [Etherscan](www.etherscan.io) and generate an API key. This is required for fetching source codes of the mainnet contracts we will be interacting with. Store the API key in the `ETHERSCAN_TOKEN` environment variable.

```bash
export ETHERSCAN_TOKEN=YourApiToken
```

- Optional Use .env file
  1. Make a copy of `.env.example`
  2. Add the values for `ETHERSCAN_TOKEN` and `WEB3_INFURA_PROJECT_ID`
     NOTE: If you set up a global environment variable, that will take precedence


## Testing

To run the tests:

```
brownie test -v
```

# Resources

