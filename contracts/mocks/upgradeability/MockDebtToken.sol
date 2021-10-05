// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {DebtToken} from '../../protocol/tokenization/DebtToken.sol';

contract MockDebtToken is DebtToken {
  function getRevision() internal pure override returns (uint256) {
    return 0x2;
  }
}
