// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

interface ITokenSwap {
    function swap(
        address _tokenIn,
        address _tokenOut,
        uint _amountIn,
        uint _amountOutMin,
        address _to
    ) external returns(uint);

    function getUniswapV2PairAddress(address token0, address token1)
        external
        view
        returns(address);
}