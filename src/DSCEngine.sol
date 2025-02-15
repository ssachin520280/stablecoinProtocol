// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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

    mapping(address token => address priceFeed) private s_priceFeeds;
    DecentralizedStableCoin private immutable i_dsc;

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

    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses,
        address _dscAddress
    ) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfSameLength();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
        }
        i_dsc = DecentralizedStableCoin(_dscAddress);
    }

    function depositCollateralAndMintDSC() external {}

    /**
    @notice Deposits collateral into the protocol to back DSC minting
    @dev Follows CEI (Checks-Effects-Interactions) pattern
    @param tokenCollateralAddress The ERC20 token address to be used as collateral
    @param amountCollateral The amount of collateral to deposit (in wei)
    @custom:requirements
    - Token must be approved as collateral in constructor
    - Amount must be > 0
    - User must have approved this contract to spend their tokens
     */
    function depositCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral
    ) 
        external 
        moreThanZero(amountCollateral) 
        isAllowedToken(tokenCollateralAddress)
        nonReentrant {

    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function healthFactor() external view {}

}