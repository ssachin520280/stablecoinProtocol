// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
        
        // Mint WETH to USER
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    // Constructor Tests

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    // function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
    //     tokenAddresses.push(weth);
    //     priceFeedAddresses.push(ethUsdPriceFeed);
    //     priceFeedAddresses.push(btcUsdPriceFeed);

    //     vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfSameLength.selector);
    //     new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    // }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedAmount = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedAmount, actualWeth);
    }

    // Price tests

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 2000/ETH
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    // depositCollateral tests

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
    }

    function testRevertsIfUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        ranToken.mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedCollateralValueInUsd);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }

    function testMintDsc() public depositedCollateral {
        uint256 amountToMint = 100 ether;
        vm.startPrank(USER);
        dsce.mintDsc(amountToMint);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountToMint);
    }

    function testRevertsIfMintAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfMintBreaksHealthFactor() public depositedCollateral {
        // Try to mint more than the collateral value
        uint256 amountToMint = 50000 ether; // Much more than the collateral value
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dsce.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositedCollateral {
        uint256 amountToMint = 100 ether;
        vm.startPrank(USER);
        dsce.mintDsc(amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.burnDsc(amountToMint);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
    }

    function testRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
    }

    function testRevertIfRedeemAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    // TODO: Add liquidation tests
    // function testLiquidation() public depositedCollateral {
    //     // Setup: USER mints maximum DSC
    //     uint256 amountToMint = 8000 ether; // Assuming this brings health factor close to minimum
    //     vm.startPrank(USER);
    //     dsce.mintDsc(amountToMint);
    //     vm.stopPrank();

    //     // Setup: Create a price drop to make USER's position liquidatable
    //     int256 newPrice = 1500e8; // Drop ETH price to $1500
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newPrice);

    //     // Setup: LIQUIDATOR gets DSC to liquidate USER
    //     address LIQUIDATOR = makeAddr("liquidator");
    //     ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL);
    //     vm.startPrank(LIQUIDATOR);
    //     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    //     dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
    //     dsc.approve(address(dsce), amountToMint);

    //     // Perform liquidation
    //     dsce.liquidate(weth, USER, amountToMint);
    //     vm.stopPrank();

    //     // Verify USER's position is liquidated
    //     (uint256 userDscMinted,) = dsce.getAccountInformation(USER);
    //     assertEq(userDscMinted, 0);
    // }

    function testRevertLiquidationIfHealthFactorOk() public depositedCollateral {
        // Try to liquidate a healthy position
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, 100);
        vm.stopPrank();
    }
}