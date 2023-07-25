// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import './Interfaces/IPreSale.sol';

contract PegasusPresale is Ownable {

    using SafeMath for uint256;
    
    IERC20 public token;
    IDexRouter public routerAddress;
    address payable public tokenOwner;

    uint256 public tokenPrice;
    uint256 public bnbFeePercent;
    uint256 public tokenFeePercent;
    uint256 public referralPercent;
    uint256 public presaleStartTime;
    uint256 public preSaleEndTime;
    uint256 public minAmount;
    uint256 public maxAmount;
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public listingPrice;
    uint256 public liquidityPercent;
    uint256 public totalUser;
    uint256 public soldTokens;
    uint256 public amountRaised;
    uint256 public percentDivider;
    uint256 public presaleCount;

    bool public allow;
    bool public canClaim;
    bool public refund;
    bool public whitelistEnable;
    bool public publicEnable;

    struct User {
        uint256 coinBalance;
        uint256 tokenBalance;
        uint256 referralBonus;
        uint256 claimedAmount;
        bool isClaimed;
    }

    mapping(address => User) public users;
    mapping(address => bool) public whitelistedUsers;

    modifier allowed(){
        require(allow == true,"Pegasus: Not allowed");
        _;
    }
    
    event tokenBought(address indexed user, uint256 indexed numberOfTokens, uint256 indexed amountBusd);

    event tokenClaimed(address indexed user, uint256 indexed numberOfTokens);

    event tokenUnSold(address indexed user, uint256 indexed numberOfTokens);

    constructor() {
        routerAddress = IDexRouter(0xD99D1c33F9fC3444f8101754aBC46c52416550D1);
        allow = true;
        publicEnable = true;
        percentDivider = 100;
    }

    // called once by the deployer contract at time of deployment
    function initialize(
        address _owner,
        address _tokenOwner,
        address _token,
        uint256[12] memory _values,
        bool _refund,
        bool _saleType,
        uint256 _presaleCount
    ) external onlyOwner {
        // 000000000000000000
        transferOwnership((payable(_owner)));
        tokenOwner = payable(_tokenOwner);
        token = IERC20(_token);
        tokenPrice = _values[0];
        bnbFeePercent = _values[1];
        tokenFeePercent = _values[2];
        referralPercent = _values[3];
        presaleStartTime = _values[4];
        preSaleEndTime = _values[5];
        minAmount = _values[6];
        maxAmount = _values[7];
        hardCap = _values[8];
        softCap = _values[9];
        listingPrice = _values[10];
        liquidityPercent = _values[11];
        refund = _refund;
        whitelistEnable = _saleType;
        presaleCount = _presaleCount;
    }

    receive() external payable {
        _buy(address(0), msg.value);
    }

    // to buy token during preSale time => for web3 use
    function buy(address referrer) public payable {
        _buy(referrer, msg.value);
    }

    function _buy(address referrer, uint256 amount) internal allowed {
        require(
            block.timestamp > presaleStartTime,
            "Pegasus: Wait for start time"
        );
        require(block.timestamp < preSaleEndTime, "Pegasus: Time over");

        if (whitelistEnable) {
            require(
                whitelistedUsers[msg.sender],
                "Pegasus: User not whitelisted"
            );
        } else {
            require(publicEnable, "Pegasus: Public sale not started");
        }

        require(amount >= minAmount, "Pegasus: Less than min amount");
        require(
            users[msg.sender].coinBalance.add(amount) <= maxAmount,
            "Pegasus: Greater than max amount"
        );
        require(
            amountRaised.add(amount) <= hardCap,
            "Pegasus: Hardcap reached"
        );

        if (users[msg.sender].coinBalance == 0) {
            totalUser++;
        }
        if (referralPercent > 0) {
            if (referrer != msg.sender && referrer != address(0)) {
                users[referrer].referralBonus = amount
                    .mul(referralPercent)
                    .div(percentDivider);
            }
        }
        uint256 numberOfTokens = bnbToToken(amount);
        users[msg.sender].tokenBalance += numberOfTokens;
        soldTokens += numberOfTokens;
        users[msg.sender].coinBalance += amount;
        amountRaised += amount;

        emit tokenBought(msg.sender, numberOfTokens, amount);
    }

    function claim() public allowed {
        require(canClaim == true, "Pegasus: Wait for admin to finalize");
        uint256 numberOfTokens;
        if (amountRaised < softCap) {
            require(!users[msg.sender].isClaimed, "Pegasus: Already claimed");
            numberOfTokens = users[msg.sender].coinBalance;
            require(numberOfTokens > 0, "Pegasus: Zero balance");
            payable(msg.sender).transfer(numberOfTokens);
            users[msg.sender].isClaimed = true;
        } else {
            require(!users[msg.sender].isClaimed, "Pegasus: Already claimed");
            numberOfTokens = users[msg.sender].tokenBalance.add(
                users[msg.sender].referralBonus
            );
            require(numberOfTokens > 0, "Pegasus: Zero balance");
            token.transfer(msg.sender, numberOfTokens);
            users[msg.sender].claimedAmount = numberOfTokens;
            users[msg.sender].isClaimed = true;
        }
        emit tokenClaimed(msg.sender, numberOfTokens);
    }

    function finalize() public onlyOwner {
        require(
            block.timestamp > preSaleEndTime || amountRaised >= hardCap,
            "Pegasus: PreSale not over yet"
        );
        canClaim = true;
        if (amountRaised > softCap) {
            uint256 bnbAmountForLiquidity = amountRaised
                .mul(liquidityPercent)
                .div(percentDivider);
            uint256 tokenAmountForLiquidity = listingTokens(
                bnbAmountForLiquidity
            );
            token.approve(address(routerAddress), tokenAmountForLiquidity);
            addLiquidity(
                tokenOwner,
                bnbAmountForLiquidity,
                tokenAmountForLiquidity
            );

            if (bnbFeePercent > 0) {
                owner().transfer(
                    amountRaised.mul(bnbFeePercent).div(percentDivider)
                );
            }
            if (tokenFeePercent > 0) {
                token.transfer(
                    owner(),
                    soldTokens.mul(bnbFeePercent).div(percentDivider)
                );
            }

            payable(tokenOwner).transfer(getContractCoinBalance());
            uint256 remainingAmount = getContractTokenBalance().sub(soldTokens);
            if (remainingAmount > 0) {
                if (refund == true) {
                    token.transfer(tokenOwner, remainingAmount);
                    emit tokenUnSold(tokenOwner, remainingAmount);
                } else {
                    token.transfer(address(0), remainingAmount);
                    emit tokenUnSold(address(0), remainingAmount);
                }
            }
        } else {
            token.transfer(owner(), getContractTokenBalance());

            emit tokenUnSold(owner(), getContractCoinBalance());
        }
    }

    function addLiquidity(
        address receiver,
        uint256 tokenAmount,
        uint256 bnbAmount
    ) internal {
        // add the liquidity
        routerAddress.addLiquidityETH{value: bnbAmount}(
            address(token),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            receiver,
            block.timestamp
        );
    }

    // to check number of token for buying
    function bnbToToken(uint256 _amount)
        public
        view
        returns (uint256 numberOfTokens)
    {
        numberOfTokens = _amount
            .mul(tokenPrice)
            .mul(10**(token.decimals()))
            .div(1 ether);
    }

    // to calculate number of tokens for listing price
    function listingTokens(uint256 _amount)
        public
        view
        returns (uint256 numberOfTokens)
    {
        numberOfTokens = _amount
            .mul(listingPrice)
            .mul(10**(token.decimals()))
            .div(1 ether);
    }

    // to Stop preSale in case of scam
    function startOrStopSale() external onlyOwner {
        if (allow == true) {
            allow = false;
        } else {
            allow = true;
        }
    }

    // to switch sale type between public and whitelist
    function switchSaleType() external onlyOwner {
        if (whitelistEnable == true) {
            whitelistEnable = false;
            publicEnable = true;
        } else {
            publicEnable = false;
            whitelistEnable = true;
        }
    }

    // to set white listed users for whitelist sale
    function setWhitelistedUsers(address[] memory _users, bool _value)
        external
        onlyOwner
    {
        for (uint32 i = 0; i < _users.length; i++) {
            whitelistedUsers[_users[i]] = _value;
        }
    }

    // to draw funds for liquidity
    function transferFunds(uint256 _value) external onlyOwner {
        owner().transfer(_value);
    }

    // to draw out tokens
    function transferTokens(uint256 _value) external onlyOwner {
        token.transfer(owner(), _value);
    }

    function getContractCoinBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getContractTokenBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    } 
    }