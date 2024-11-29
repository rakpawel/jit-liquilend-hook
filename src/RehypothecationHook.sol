// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {IPool} from "./interfaces/IPool.sol";
import "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

contract RehypothecationHook is BaseHook, ERC20 {
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using StateLibrary for IPoolManager;

    struct AddLiquidityParams {
        uint24 fee;
        Currency currency0;
        Currency currency1;
        uint256 amount0;
        uint256 amount1;
        int24 tickLower;
        int24 tickUpper;
        int24 tickSpacing;
        PoolKey key;
    }

    struct RemoveLiquidityParams {
        Currency currency0;
        Currency currency1;
        address sender;
        uint128 liquidity;
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
        int24 tickSpacing;
        PoolKey key;
    }

    error PoolNotInitialized();

    IPool public aavePool;
    uint256 public percentageDeposit;
    uint256 public THRESHOLD;

    constructor(
        IPoolManager _manager,
        string memory _name,
        string memory _symbol,
        address _aavePool,
        uint256 _percentageDeposit
    ) BaseHook(_manager) ERC20(_name, _symbol, 18) {
        aavePool = IPool(_aavePool);
        percentageDeposit = _percentageDeposit;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: true,
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

    function addLiquidity(AddLiquidityParams calldata params) external {
        PoolKey memory key = PoolKey({
            currency0: params.currency0,
            currency1: params.currency1,
            fee: params.fee,
            tickSpacing: params.tickSpacing,
            hooks: IHooks(address(this))
        });
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(
            params.key.toId()
        );
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        uint128 poolLiquidity = poolManager.getLiquidity(params.key.toId());
        uint256 amount0ToAdd = (params.amount0 * percentageDeposit) / 100;
        uint256 amount1ToAdd = (params.amount1 * percentageDeposit) / 100;
        uint256 amount0ToDeposit = params.amount0 - amount0ToAdd;
        uint256 amount1ToDeposit = params.amount1 - amount1ToAdd;
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(params.tickLower),
            TickMath.getSqrtPriceAtTick(params.tickUpper),
            amount0ToAdd,
            amount1ToAdd
        );

        ERC20(Currency.unwrap(params.currency0)).transferFrom(
            msg.sender,
            address(this),
            amount0ToAdd
        );
        ERC20(Currency.unwrap(params.currency1)).transferFrom(
            msg.sender,
            address(this),
            amount1ToAdd
        );

        // Supply to Aave
        _supplyToAave(Currency.unwrap(params.currency0), amount0ToAdd);
        _supplyToAave(Currency.unwrap(params.currency1), amount1ToAdd);

        //TODO: deposit to aave and pool
        _mint(msg.sender, liquidity);
    }

    function removeLiquidity(RemoveLiquidityParams calldata params) external {
        PoolKey memory key = PoolKey({
            currency0: params.currency0,
            currency1: params.currency1,
            fee: params.fee,
            tickSpacing: params.tickSpacing,
            hooks: IHooks(address(this))
        });

        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(
            params.key.toId()
        );
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        //TODO: withdraw from aave and pool
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
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
        uint128 poolLiquidity = poolManager.getLiquidity(poolId);

        uint160 newSqrtPriceX96 = estimateNewSqrtPrice(
            sqrtPriceX96,
            params.amountSpecified,
            poolLiquidity,
            params.zeroForOne
        );

        uint256 priceImpact = calculatePriceImpact(sqrtPriceX96, sqrtPriceX96);
        if (priceImpact > THRESHOLD) {
            //TODO: withdraw from aave and pool
        }
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, int128) {
        return (this.afterSwap.selector, 0);
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        return (this.afterAddLiquidity.selector, delta);
    }

    function _supplyToAave(address asset, uint256 amount) internal {
        // Approve the Aave pool to spend the token
        ERC20(asset).approve(address(aavePool), amount);

        // Supply the asset to Aave
        aavePool.supply(asset, amount, address(this), 0);
    }

    function estimateNewSqrtPrice(
        uint160 sqrtPriceX96,
        int256 amountSpecified,
        uint128 liquidity,
        bool zeroForOne
    ) internal pure returns (uint160) {
        if (amountSpecified == 0) {
            return sqrtPriceX96;
        }

        bool isPositiveAmount = amountSpecified > 0;
        uint256 absAmount = isPositiveAmount
            ? uint256(amountSpecified)
            : uint256(-amountSpecified);

        // For zeroForOne:
        //   - positive amount -> price down -> amount0 -> roundUp
        //   - negative amount -> price up -> amount1 -> roundDown
        // For !zeroForOne:
        //   - positive amount -> price up -> amount1 -> roundDown
        //   - negative amount -> price down -> amount0 -> roundUp
        bool useAmount0 = zeroForOne == isPositiveAmount;

        return
            useAmount0
                ? SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                    sqrtPriceX96,
                    liquidity,
                    absAmount,
                    true
                )
                : SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                    sqrtPriceX96,
                    liquidity,
                    absAmount,
                    true
                );
    }

    function calculatePriceImpact(
        uint160 currentSqrtPriceX96,
        uint160 newSqrtPriceX96
    ) internal pure returns (uint256) {
        // Use absDiff from SqrtPriceMath for safer arithmetic
        uint256 sqrtPriceDiff = SqrtPriceMath.absDiff(
            currentSqrtPriceX96,
            newSqrtPriceX96
        );

        // Calculate relative price change using the sqrt values directly
        // This avoids the need to fully square the values which could cause overflow
        // (sqrtDiff * 2 * 1e4) / currentSqrtPrice gives us basis points
        return
            FullMath.mulDivRoundingUp(
                sqrtPriceDiff * 2,
                FixedPoint96.Q96,
                currentSqrtPriceX96
            ) / 100; // Convert to basis points
    }
}
