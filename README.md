# JIT-LiquiLend-Hook

## Overview

**JIT-LiquiLend-Hook** is a project that leverages **Uniswap V4 Hooks** to provide **just-in-time liquidity** and **yield earning** via **Aave** when liquidity is not actively utilized during swaps. The project also integrates **EigenLayer AVS** to determine the current price and ideal tick range for JIT liquidity based on recent market volatility. This system optimizes liquidity utilization by automatically shifting idle liquidity to the Aave lending protocol for passive yield generation.

This solution is built using the **Foundry framework** and allows liquidity providers to maximize their returns by earning yield on their idle liquidity.

## Features

- **Just-in-Time Liquidity**: Liquidity is provided to Uniswap V4 pools only when required, reducing opportunity cost.
- **Idle Liquidity Yielding**: Idle liquidity is lent out on Aave to earn interest while it's not being used in swaps.
- **Automated Liquidity Management**: The system moves liquidity between Uniswap V4 pools and Aave based on usage, ensuring optimal yield generation.
- **EigenLayer AVS Integration**: Uses **EigenLayer AVS** to fetch the current price and ideal tick range for liquidity provision, ensuring that liquidity is provided within an optimal range.

## Technologies Used

- **Uniswap V4**: Decentralized exchange with hooks to customize liquidity management.
- **Aave**: Decentralized lending protocol to earn passive yield on idle liquidity.
- **EigenLayer AVS**: Used to determine the current price and optimal tick range for liquidity.
- **Foundry**: Ethereum development framework for building and testing smart contracts.
- **Solidity**: Programming language for smart contract development.

## Architecture

- **Uniswap V4 Hooks**: Allows for custom logic based on swap events, enabling dynamic liquidity management.
- **Aave Integration**: Idle liquidity is automatically lent out to Aave to earn yield.
- **EigenLayer AVS**: Provides real-time price data and calculates the ideal tick range for liquidity provision.
- **Foundry**: Used for compiling, deploying, and testing smart contracts efficiently.

![Screenshot 2024-12-03 161638](https://github.com/user-attachments/assets/080daca9-e99c-4104-9bb0-754a977b1982)


## Getting Started

### Prerequisites

Before you can start using the project, ensure you have the following installed:

- **Foundry**: Install it following the instructions on [Foundry's official website](https://book.getfoundry.sh/).
- **Node.js**: Required for managing dependencies and running scripts. Install it from [Node.js official website](https://nodejs.org/).
- **Solidity**: The smart contracts are written in Solidity, ensure you have a compatible version of Solidity.

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/rakpawel/jit-liquilend-hook.git
   cd JIT-LiquiLend-Hook
   ```
2. ```shell
    $ forge install
    ```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Anvil

```shell
$ anvil
```
