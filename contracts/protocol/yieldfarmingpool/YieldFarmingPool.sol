// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {VersionedInitializable} from '../libraries/wevest-upgradeability/VersionedInitializable.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {IYieldFarmingPool} from '../../interfaces/IYieldFarmingPool.sol';
import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';

contract YieldFarmingPool is VersionedInitializable, IYieldFarmingPool {

    uint256 public constant YIELDFARMING_POOL_REVISION = 0x2;

    ILendingPoolAddressesProvider internal _addressesProvider;

    function initialize(ILendingPoolAddressesProvider provider) public initializer {
        _addressesProvider = provider;
    }

    function getRevision() internal pure override returns (uint256) {
        return YIELDFARMING_POOL_REVISION;
    }
}