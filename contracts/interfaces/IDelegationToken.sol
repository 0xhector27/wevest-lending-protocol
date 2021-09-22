// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

/**
 * @title IDelegationToken
 * @dev Implements an interface for tokens with delegation COMP/UNI compatible
 **/
interface IDelegationToken {
  function delegate(address delegatee) external;
}
