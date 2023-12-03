// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";

// This is a practice contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {
    struct CallbackData {
        address priceLowerPool;
        address priceHigherPool;
        uint beforeBalance;
        address borrowToken;
        address paybackToken;
        uint borrowAmount;
        uint paybackAmount;
    }

    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //
    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        // Method 1
        // validate
        CallbackData memory callbackData = abi.decode(data, (CallbackData));
        require(sender == address(this), "Callback sender must be self.");
        require(msg.sender == callbackData.priceLowerPool, "Callback must from priceLowerPool.");
        require(amount0 > 0 || amount1 > 1, "Insufficient amount.");
        require((IERC20(callbackData.borrowToken).balanceOf(address(this)) - callbackData.beforeBalance) == callbackData.borrowAmount, "Incorrect borrow amount.");
        // swap WETH to USDC in priceHigherPool
        IERC20(callbackData.borrowToken).approve(address(this), callbackData.borrowAmount);
        IERC20(callbackData.borrowToken).transferFrom(address(this), callbackData.priceHigherPool, callbackData.borrowAmount);
        (uint _reserve0, uint _reserve1, ) = IUniswapV2Pair(callbackData.priceHigherPool).getReserves();
        uint _amountOut = _getAmountOut(callbackData.borrowAmount, _reserve0, _reserve1);
        IUniswapV2Pair(callbackData.priceHigherPool).swap(0, _amountOut, address(this), "");
        // payback to priceLowerPool
        IERC20(callbackData.paybackToken).transfer(callbackData.priceLowerPool, callbackData.paybackAmount);
    }

    // Method 1 is
    // - borrow WETH from lower price pool
    // - swap WETH for USDC in higher price pool
    // - repay USDC to lower pool
    // Method 2 is
    // - borrow USDC from higher price pool
    // - swap USDC for WETH in lower pool
    // - repay WETH to higher pool
    // for testing convenient, we implement the method 1 here
    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        // Method 1
        // validate
        require(borrowETH > 0, "borrow amount must > 0.");
        // borrow WETH from priceLowerPool
        (uint _reserve0, uint _reserve1, ) = IUniswapV2Pair(priceLowerPool).getReserves();
        uint _amountIn = _getAmountIn(borrowETH, _reserve1, _reserve0);
        (address _borrowToken, address _paybackToken) = (IUniswapV2Pair(priceLowerPool).token0(), IUniswapV2Pair(priceLowerPool).token1());
        uint _beforeBalance = IERC20(_borrowToken).balanceOf(address(this));
        CallbackData memory callbackData = CallbackData(priceLowerPool, priceHigherPool, _beforeBalance, _borrowToken, _paybackToken, borrowETH, _amountIn);
        IUniswapV2Pair(priceLowerPool).swap(borrowETH, 0, address(this), abi.encode(callbackData));
    }

    //
    // INTERNAL PURE
    //
    // copy from UniswapV2Library
    function _getAmountIn(
    uint256 amountOut,
    uint256 reserveIn,
    uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
