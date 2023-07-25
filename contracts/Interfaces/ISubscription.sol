// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IERC20.sol";
import "../Libraries/SafeMath.sol";
import "../Interfaces/IDexRouter.sol";
import "../AbstractContracts/Ownable.sol";

interface ISubscription {

    function initialize(
        address _owner,
        address _tokenOwner,
        address _token,
        uint256[13] memory _values,
        bool _refund,
        bool _saleType,
        uint256 presaleCount
    ) external;
}
