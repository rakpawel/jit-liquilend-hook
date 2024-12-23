// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Hook} from "../src/Hook.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IPool} from "../src/interfaces/IPool.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

contract MockElAvs {
    address public constant EL_AVS = address(0x1);
}

contract MockAavePool {
    mapping(address => address) public aTokens;
    constructor(address[] memory assets) {
        for (uint256 i = 0; i < assets.length; i++) {
            aTokens[assets[i]] = address(new MockERC20("Aave", "aToken", 18));
        }
    }

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external {
        ERC20(asset).transferFrom(msg.sender, address(this), amount);
        MockERC20(aTokens[asset]).mint(msg.sender, amount);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        ERC20(asset).transfer(to, amount);
        MockERC20(aTokens[asset]).burn(msg.sender, amount);
        return amount;
    }

    function getReserveData(
        address asset
    ) external view returns (IPool.ReserveData memory) {
        return
            IPool.ReserveData({
                aTokenAddress: aTokens[asset],
                stableDebtTokenAddress: address(asset),
                variableDebtTokenAddress: address(asset),
                interestRateStrategyAddress: address(asset),
                accruedToTreasury: 0,
                id: 0,
                unbacked: 0,
                isolationModeTotalDebt: 0,
                lastUpdateTimestamp: 0,
                liquidityIndex: 0,
                currentLiquidityRate: 0,
                variableBorrowIndex: 0,
                currentVariableBorrowRate: 0,
                currentStableBorrowRate: 0,
                configuration: IPool.ReserveConfigurationMap(0)
            });
    }
}

contract TestHook is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    Hook hook;

    MockAavePool lendingProtocol;
    MockElAvs elAvs;

    function setUp() public {
        // Deploy v4-core
        deployFreshManagerAndRouters();

        // Deploy, mint tokens, and approve all periphery contracts for two tokens
        deployMintAndApprove2Currencies();

        // Deploy our hook with the proper flags
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.AFTER_SWAP_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            )
        );

        // Set gas price = 10 gwei and deploy our hook
        vm.txGasPrice(10 gwei);
        address[] memory assets = new address[](2);
        assets[0] = Currency.unwrap(currency0);
        assets[1] = Currency.unwrap(currency1);
        lendingProtocol = new MockAavePool(assets);
        elAvs = new MockElAvs();
        deployCodeTo(
            "Hook",
            abi.encode(manager, lendingProtocol, elAvs),
            hookAddress
        );
        hook = Hook(hookAddress);

        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1000 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1000 ether);

        MockERC20(Currency.unwrap(currency0)).mint(address(elAvs), 1000 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(elAvs), 1000 ether);
        // Initialize a pool
        (key, ) = initPool(
            currency0,
            currency1,
            hook,
            3000, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee
            SQRT_PRICE_1_1
        );

        // initialize initial small-liquidity
        MockERC20(Currency.unwrap(currency0)).mint(msg.sender, 1000 ether);
        MockERC20(Currency.unwrap(currency1)).mint(msg.sender, 1000 ether);
        MockERC20(Currency.unwrap(currency0)).approve(
            address(modifyLiquidityRouter),
            1000 ether
        );
        MockERC20(Currency.unwrap(currency1)).approve(
            address(modifyLiquidityRouter),
            1000 ether
        );
        int24 tickLower = (TickMath.MIN_TICK / key.tickSpacing) *
            key.tickSpacing;
        int24 tickUpper = (TickMath.MAX_TICK / key.tickSpacing) *
            key.tickSpacing;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmounts(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            1 ether,
            1 ether
        );
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int128(liquidityDelta),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_addLiquidity() public {
        address user = address(999);
        vm.startPrank(user);
        MockERC20(Currency.unwrap(currency0)).mint(user, 1000 ether);
        MockERC20(Currency.unwrap(currency1)).mint(user, 1000 ether);
        MockERC20(Currency.unwrap(currency0)).approve(address(hook), 100 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(hook), 100 ether);
        hook.addLiquidity(
            Hook.LiquidityParams({
                fee: 60,
                currency0: currency0,
                currency1: currency1,
                amount0: 100 ether,
                amount1: 100 ether,
                key: key
            })
        );

        assertEq(
            ERC20(Currency.unwrap(currency0)).balanceOf(
                address(lendingProtocol)
            ),
            100 ether
        );
        assertEq(
            ERC20(Currency.unwrap(currency1)).balanceOf(
                address(lendingProtocol)
            ),
            100 ether
        );
        assertEq(
            MockERC20(lendingProtocol.aTokens(Currency.unwrap(currency0)))
                .balanceOf(address(hook)),
            100 ether
        );
        assertEq(
            MockERC20(lendingProtocol.aTokens(Currency.unwrap(currency1)))
                .balanceOf(address(hook)),
            100 ether
        );
        vm.stopPrank();
    }

    function test_AVSSwap() public {
        test_addLiquidity();
        manager.unlock(abi.encode(address(elAvs)));
        assertEq(hook.getTickLower(), -60);
        assertEq(hook.getTickUpper(), 60);
    }

    function test_UserSwap1() public {
        test_addLiquidity();
        manager.unlock(abi.encode(address(1234)));
        assertEq(hook.getTickLower(), TickMath.MIN_TICK / 60 * 60);
        assertEq(hook.getTickUpper(), TickMath.MAX_TICK / 60 * 60);
    }

    function test_UserSwap2() public {
        test_AVSSwap();
        manager.unlock(abi.encode(address(1234)));
        assertEq(hook.getTickLower(), -60);
        assertEq(hook.getTickUpper(), 60);
    }

    function unlockCallback(
        bytes calldata rawData
    ) external returns (bytes memory) {
        address actor = abi.decode(rawData, (address));
        int256 swapAmount = actor == address(elAvs) ? -0.00001 ether : -1 ether;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: swapAmount,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        vm.startPrank(actor);
        bytes memory tickParams = actor == address(elAvs)
            ? abi.encode(int24(-60), int24(60))
            : ZERO_BYTES;
        BalanceDelta delta = manager.swap(key, params, tickParams);
        manager.sync(currency0);
        uint256 swapAmount0 = actor == address(elAvs) ? 0.00001 ether : 1 ether;
        MockERC20(Currency.unwrap(currency0)).mint(
            actor,
            swapAmount0
        );
        MockERC20(Currency.unwrap(currency0)).transfer(
            address(manager),
            swapAmount0
        );
        manager.take(
            currency1,
            address(actor),
            uint256(int256(delta.amount1()))
        );
        manager.settle();
        vm.stopPrank();
    }
}
