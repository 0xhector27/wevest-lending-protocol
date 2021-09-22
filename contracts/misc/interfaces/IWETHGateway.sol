// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

interface IWETHGateway {
  function depositETH(
    address lendingPool
  ) external payable;

  function withdrawETH(
    address lendingPool,
    uint256 amount
  ) external;

  function repayETH(
    address lendingPool,
    uint256 amount
  ) external payable;

  function borrowETH(
    address lendingPool,
    uint256 amount,
    uint256 leverageRatioMode
  ) external;
}
