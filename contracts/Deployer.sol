/**
 __   ___  __        __        __  
|__) |__  / _`  /\  /__` |  | /__` 
|    |___ \__> /~~\ .__/ \__/ .__/ 
                                   
 */
// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./PegasusPresale.sol";

contract PresaleDeployer is Ownable {
    using SafeMath for uint256;
    address public token;
    uint256 public percentDivider;
    uint256 public presaleCount;

    mapping(address => bool) public isPreSaleExist;
    mapping(address => address) public getPreSale;
    address[] public allPreSales;

    event PreSaleCreated(
        address indexed _token,
        address indexed _preSale,
        uint256 indexed _length
    );

    constructor() {
        percentDivider = 1000;
    }

    function createPreSaleBNB(
        address _tokenOwner,
        address _token,
        uint256[12] memory _values,
        bool _refund,
        bool _saleType
    ) external returns (address preSaleContract) {
        token = _token;
        require(token != address(0), "Pegasus: ZERO_ADDRESS");
        require(
            isPreSaleExist[address(token)] == false,
            "Pegasus: PRESALE_EXISTS"
        ); // single check is sufficient

        bytes memory bytecode = type(PegasusPresale).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token, msg.sender));

        assembly {
            preSaleContract := create2(
                0,
                add(bytecode, 32),
                mload(bytecode),
                salt
            )
        }

        IPreSale(preSaleContract).initialize(
            owner(),
            _tokenOwner,
            token,
            _values,
            _refund,
            _saleType,
            presaleCount++
        );

        getPreSale[address(token)] = preSaleContract;
        // isPreSaleExist[address(token)] = true; // setting preSale for this token to aviod duplication
        allPreSales.push(preSaleContract);

        emit PreSaleCreated(
            address(token),
            preSaleContract,
            allPreSales.length
        );
    }

    function getTotalNumberOfTokens(
        address _token,
        uint256 _tokenPrice,
        uint256 _listingPrice,
        uint256 _hardCap,
        uint256 _liquidityPercent,
        uint256 _adminFee
    ) public view returns (uint256 tokensForSell,uint256 tokensForListing) {
        tokensForSell = _hardCap.mul(_tokenPrice);
        if (_adminFee > 0) {
            uint256 adminFee = tokensForSell.mul(_adminFee).div(1000);
            tokensForSell += adminFee;
        }
        tokensForListing = (_hardCap.mul(_liquidityPercent).div(100))
            .mul(_listingPrice);
        tokensForListing = tokensForListing.mul(10**(IERC20(_token).decimals())).div(1 ether);
        tokensForSell = tokensForSell.mul(10**(IERC20(_token).decimals())).div(1 ether);
    }

    function setPercentDivider(uint256 _value) external onlyOwner {
        percentDivider = _value;
    }

    function getAllPreSalesLength() external view returns (uint256) {
        return allPreSales.length;
    }
}