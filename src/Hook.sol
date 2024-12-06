// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IPool} from "./interfaces/IPool.sol";

contract Hook is BaseHook {
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using StateLibrary for IPoolManager;

    struct LiquidityParams {
        uint24 fee;
        Currency currency0;
        Currency currency1;
        uint256 amount0;
        uint256 amount1;
        PoolKey key;
    }

    error PoolNotInitialized();

    IPool public lendingProtocol;

    int24 public tickLower;
    int24 public tickUpper;
    int24 internal constant MIN_TICK = -887220;
    int24 internal constant MAX_TICK = -MIN_TICK;
    address public EL_AVS;
    uint256 public totalToken0Shares;
    uint256 public totalToken1Shares;
    uint128 private liquidityAdded;
    bool private liquidityInitialized;

    mapping(address user => uint256 shares) public token0Shares;
    mapping(address user => uint256 shares) public token1Shares;

    constructor(
        IPoolManager _manager,
        address _aavePool,
        address _elAvs
    ) BaseHook(_manager) {
        lendingProtocol = IPool(_aavePool);
        EL_AVS = _elAvs;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function addLiquidity(LiquidityParams calldata params) external {
        // Transfer tokens from user to hook contract
        // Mint shares to user
        // Deposit tokens to lending protocol
        if (params.amount0 > 0) {
            IERC20(Currency.unwrap(params.key.currency0)).transferFrom(
                msg.sender,
                address(this),
                params.amount0
            );
            uint256 amount0 = IERC20(Currency.unwrap(params.key.currency0))
                .balanceOf(address(this));
            uint256 shares;
            if (totalToken0Shares == 0) {
                shares = params.amount0;
            } else {
                shares = (params.amount0 * totalToken0Shares) / amount0;
            }
            token0Shares[msg.sender] += shares;
            totalToken0Shares += shares;
            IERC20(Currency.unwrap(params.key.currency0)).approve(
                address(lendingProtocol),
                params.amount0
            );
            lendingProtocol.supply(
                Currency.unwrap(params.key.currency0),
                params.amount0,
                address(this),
                0
            );
        }

        if (params.amount1 > 0) {
            IERC20(Currency.unwrap(params.key.currency1)).transferFrom(
                msg.sender,
                address(this),
                params.amount1
            );
            uint256 amount1 = IERC20(Currency.unwrap(params.key.currency1))
                .balanceOf(address(this));
            uint256 shares;
            if (totalToken1Shares == 0) {
                shares = params.amount1;
            } else {
                shares = (params.amount1 * totalToken1Shares) / amount1;
            }
            token1Shares[msg.sender] += shares;
            totalToken1Shares += shares;
            IERC20(Currency.unwrap(params.key.currency1)).approve(
                address(lendingProtocol),
                params.amount1
            );
            lendingProtocol.supply(
                Currency.unwrap(params.key.currency1),
                params.amount1,
                address(this),
                0
            );
        }
    }

    function removeLiquidity(LiquidityParams calldata params) external {
        // Withdraw tokens from lending protocol
        // Burn shares from user
        // Transfer tokens to user
        if (params.amount0 > 0) {
            address aToken0 = getATokenAddress(
                Currency.unwrap(params.key.currency0)
            );
            uint256 amount0 = IERC20(aToken0).balanceOf(address(this));
            uint256 shares = (params.amount0 * totalToken0Shares) / amount0;
            token0Shares[msg.sender] -= shares;
            totalToken0Shares -= shares;
            lendingProtocol.withdraw(
                Currency.unwrap(params.key.currency0),
                params.amount0,
                address(this)
            );
            IERC20(Currency.unwrap(params.key.currency0)).transfer(
                msg.sender,
                params.amount0
            );
        }

        if (params.amount1 > 0) {
            address aToken1 = getATokenAddress(
                Currency.unwrap(params.key.currency1)
            );
            uint256 amount1 = IERC20(aToken1).balanceOf(address(this));
            uint256 shares = (params.amount1 * totalToken1Shares) / amount1;
            token1Shares[msg.sender] -= shares;
            totalToken1Shares -= shares;
            lendingProtocol.withdraw(
                Currency.unwrap(params.key.currency1),
                params.amount1,
                address(this)
            );
            IERC20(Currency.unwrap(params.key.currency1)).transfer(
                msg.sender,
                params.amount1
            );
        }
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata hookData
    )
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        if (sender == EL_AVS) {
            (tickLower, tickUpper) = abi.decode(hookData, (int24, int24));
            return (
                this.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }
        // Withdraw from lending protocol
        address aToken0 = getATokenAddress(Currency.unwrap(key.currency0));
        lendingProtocol.withdraw(
            Currency.unwrap(key.currency0),
            IERC20(aToken0).balanceOf(address(this)),
            address(this)
        );
        address aToken1 = getATokenAddress(Currency.unwrap(key.currency1));
        lendingProtocol.withdraw(
            Currency.unwrap(key.currency1),
            IERC20(aToken1).balanceOf(address(this)),
            address(this)
        );

        uint256 amount0 = IERC20(Currency.unwrap(key.currency0)).balanceOf(
            address(this)
        );
        uint256 amount1 = IERC20(Currency.unwrap(key.currency1)).balanceOf(
            address(this)
        );
        // Approve tokens to pool
        IERC20(Currency.unwrap(key.currency0)).approve(
            address(poolManager),
            amount0
        );
        IERC20(Currency.unwrap(key.currency1)).approve(
            address(poolManager),
            amount1
        );

        if (tickLower == 0 && tickUpper == 0) {
            tickLower = MIN_TICK;
            tickUpper = MAX_TICK;
        }

        // add liquidity to pool
        liquidityAdded = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );

        poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int128(liquidityAdded),
                salt: bytes32(0)
            }),
            hookData
        );

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, int128) {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(
            poolId
        );

        if (sender == EL_AVS) {
            if (currentTick < tickLower || currentTick > tickUpper)
                revert("Invalid tick by AVS");
            return (this.afterSwap.selector, 0);
        }

        // Remove Liquidity
        poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: -(int128(liquidityAdded)),
                salt: bytes32(0)
            }),
            hookData
        );

        // // Calculate tokens amount
        // (uint256 amount0, uint256 amount1) = LiquidityAmounts
        //     .getAmountsForLiquidity(
        //         sqrtPriceX96,
        //         TickMath.getSqrtPriceAtTick(tickLower),
        //         TickMath.getSqrtPriceAtTick(tickUpper),
        //         liquidityAdded
        //     );
        uint256 amount0 = IERC20(Currency.unwrap(key.currency0)).balanceOf(
            address(this)
        );
        uint256 amount1 = IERC20(Currency.unwrap(key.currency1)).balanceOf(
            address(this)
        );
        // approve tokens to lending protocol
        IERC20(Currency.unwrap(key.currency0)).approve(
            address(lendingProtocol),
            amount0
        );
        IERC20(Currency.unwrap(key.currency1)).approve(
            address(lendingProtocol),
            amount1
        );

        // Deposit tokens to lending protocol
        lendingProtocol.supply(
            Currency.unwrap(key.currency0),
            amount0,
            address(this),
            0
        );
        lendingProtocol.supply(
            Currency.unwrap(key.currency1),
            amount1,
            address(this),
            0
        );

        return (this.afterSwap.selector, 0);
    }

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4) {
        if (liquidityInitialized) revert("Add Liquidity thorugh Hook");
        liquidityInitialized = true;
        return this.beforeAddLiquidity.selector;
    }

    function getATokenAddress(address asset) internal view returns (address) {
        return lendingProtocol.getReserveData(asset).aTokenAddress;
    }

    function getTickLower() external view returns (int24) {
        return tickLower;
    }

    function getTickUpper() external view returns (int24) {
        return tickUpper;
    }
}
