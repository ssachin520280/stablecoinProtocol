// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine (Decentralized Stablecoin Engine)
 * @author Sachin Anand
 * @notice This is the core contract of the DSC System that handles all business logic
 * @dev This contract handles the collateral deposits, minting, redemption, and liquidation logic
 *
 * The system works as follows:
 * - Users deposit collateral (WETH, WBTC)
 * - Users can borrow DSC against their collateral
 * - Maintains 1 DSC = 1 USD peg through overcollateralization
 *
 * Core Properties:
 * - Exogenous Collateral: Backed by assets outside the protocol (WETH, WBTC)
 * - Dollar Pegged: 1 DSC = 1 USD
 * - Algorithmically Stable: No governance, pure code-based decisions
 * - Overcollateralized: Each DSC is backed by > $1 of collateral
 *
 * Inspiration:
 * This system is similar to MakerDAO's DAI but with key differences:
 * - No governance
 * - No stability fees
 * - Only WETH and WBTC as collateral
 * - Simplified, minimal implementation
 *
 * @custom:security-contact sachin@example.com
 */
contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__MintFailed();

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 20;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    DecentralizedStableCoin private immutable I_DSC;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address from, address indexed to, address indexed token, uint256 indexed amount);

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(address[] memory _tokenAddresses, address[] memory _priceFeedAddresses, address _dscAddress) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfSameLength();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        I_DSC = DecentralizedStableCoin(_dscAddress);
    }

    /**
     * @notice Deposits collateral and mints DSC in a single transaction
     * @param _tokenCollateralAddress The ERC20 token address to be used as collateral
     * @param _amountCollateral The amount of collateral to deposit (in wei)
     * @param _amountDscToMint The amount of DSC to mint (in wei)
     * @dev This is a convenience function that combines depositCollateral() and mintDsc()
     * @custom:requirements
     * - Token must be approved as collateral in constructor
     * - Collateral amount must be > 0
     * - User must have approved this contract to spend their tokens
     * - Health factor must remain >= MIN_HEALTH_FACTOR after minting
     */
    function depositCollateralAndMintDsc(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountDscToMint
    ) external {
        depositCollateral(_tokenCollateralAddress, _amountCollateral);
        mintDsc(_amountDscToMint);
    }

    /**
     * @notice Deposits collateral into the protocol to back DSC minting
     * @dev Follows CEI (Checks-Effects-Interactions) pattern
     * @param tokenCollateralAddress The ERC20 token address to be used as collateral
     * @param amountCollateral The amount of collateral to deposit (in wei)
     * @custom:requirements
     * - Token must be approved as collateral in constructor
     * - Amount must be > 0
     * - User must have approved this contract to spend their tokens
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Redeems collateral and burns DSC in a single transaction
     * @param tokenCollateralAddress The ERC20 token address to be used as collateral
     * @param amountCollateral The amount of collateral to redeem (in wei)
     * @param amountDscToBurn The amount of DSC to burn (in wei)
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks the health factor
    }

    // in order to redeem collateral:
    // 1. health factor must be above 1 AFTER collateral pulled
    // DRY: Don't repeat yourself
    // CEI: Check, Effect, Interaction
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Mints DSC tokens to the caller based on their deposited collateral
     * @dev Minting is only allowed if the user has sufficient collateral
     * @param amountDscToMint The amount of DSC to mint (in wei)
     * @custom:requirements
     * - User must have deposited collateral
     * - The health factor must be above MIN_HEALTH_FACTOR after minting
     * - Amount must be > 0
     */
    function mintDsc(uint256 amountDscToMint) 
        public 
        moreThanZero(amountDscToMint) 
        nonReentrant 
    {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = I_DSC.mint(msg.sender, amountDscToMint);
        if(!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @dev Low-level internal function, do not call unless the function calling it 
     * is checking for health factors being broken
     * @param amount amount of DSC to burn
     */
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        I_DSC.burn(amount);
    }

    /**
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the user's funds
     * @notice The function working assumes the protocol will be roughly 200% overcollateralized
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidators
     * @notice For eg: If the price of the collateral plummeted before anyone could be liquidated.
     * @param collateralToken The token to be liquidated
     * @param user The user to be liquidated (the one who has broken the health factor)
     * @param debtToCover The amount of DSC you want to burn to improve the user's health factor
     */
    function liquidate(
        address collateralToken,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        // Check health factor
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateralToken, totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = I_DSC.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Return how close to liquidation a user is.
     * If a user goes below 1, then they can get liquidated
     * @param user : user address
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 colateralValueInUsd) = _getAccountInformation(user);
        
        uint256 collateralAdjustedForThreshold = (colateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        return collateralAdjustedForThreshold / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Check health factor
        // 2. Revert if it is down
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken();
        }
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for(uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount); 
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,, ) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address user) external view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }
}
