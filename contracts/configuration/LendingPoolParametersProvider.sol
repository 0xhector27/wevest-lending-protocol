// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.6.0;

import "../libraries/openzeppelin-upgradeability/VersionedInitializable.sol";
import "./UintStorage.sol";

/**
* @notice stores the configuration parameters of the Lending Pool contract
**/

contract LendingPoolParametersProvider is VersionedInitializable {

    uint256 constant private DATA_PROVIDER_REVISION = 0x1;

    function getRevision() internal pure override returns(uint256) {
        return DATA_PROVIDER_REVISION;
    }

    /**
    * @dev initializes the LendingPoolParametersProvider after it's added to the proxy
    * @param _addressesProvider the address of the LendingPoolAddressesProvider
    */
    function initialize(address _addressesProvider) public initializer {
    }
}
