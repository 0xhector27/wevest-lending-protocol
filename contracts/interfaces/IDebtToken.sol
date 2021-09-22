// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {IInitializableDebtToken} from './IInitializableDebtToken.sol';

/**
 * @title IDebtToken
 * @notice Defines the interface for the debt token
 * @dev It does not inherit from IERC20 to save in code size
 **/

interface IDebtToken is IInitializableDebtToken {
  /**
   * @dev Emitted when new debt is minted
   * @param user The address of the user who triggered the minting, The recipient of debt tokens
   * @param amount The amount minted
   * @param currentBalance The current balance of the user
   * @param newTotalSupply The new total supply of the debt token after the action
   **/
  event Mint(
    address indexed user,
    uint256 amount,
    uint256 currentBalance,
    uint256 newTotalSupply
  );

  /**
   * @dev Emitted when new debt is burned
   * @param user The address of the user
   * @param amount The amount being burned
   * @param currentBalance The current balance of the user
   * @param newTotalSupply The new total supply of the debt token after the action
   **/
  event Burn(
    address indexed user,
    uint256 amount,
    uint256 currentBalance,
    uint256 newTotalSupply
  );

  /**
   * @dev Mints debt token to the user address.
   * - The resulting rate is the weighted average between the rate of the new debt
   * and the rate of the previous debt
   * @param user The address receiving the debt tokens
   * @param amount The amount of debt tokens to mint
   **/
  function mint(
    address user,
    uint256 amount
  ) external returns (bool);

  /**
   * @dev Burns debt of `user`
   * - The resulting rate is the weighted average between the rate of the new debt
   * and the rate of the previous debt
   * @param user The address of the user getting his debt burned
   * @param amount The amount of debt tokens getting burned
   **/
  function burn(address user, uint256 amount) external;

  /**
   * @dev Returns the timestamp of the last update of the user
   * @return The timestamp
   **/
  function getUserLastUpdated(address user) external view returns (uint40);

  /**
   * @dev Returns the timestamp of the last update of the total supply
   * @return The timestamp
   **/
  function getTotalSupplyLastUpdated() external view returns (uint40);

  /**
   * @dev Returns the total supply
   **/
  function getTotalSupply() external view returns (uint256);

  /**
   * @dev Returns the principal debt balance of the user
   * @return The debt balance of the user since the last burn/mint action
   **/
  function principalBalanceOf(address user) external view returns (uint256);
}
