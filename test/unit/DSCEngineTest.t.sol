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

    function testConstructorRevertsWithUnequalArrays() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

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

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testRevertIfBurnAmountExceedsBalance() public depositedCollateral {
        uint256 amountToMint = 100 ether;
        vm.startPrank(USER);
        dsce.mintDsc(amountToMint);
        
        vm.expectRevert(); // Will revert on transfer since amount exceeds balance
        dsce.burnDsc(amountToMint + 1);
        vm.stopPrank();
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

    function testRevertRedeemCollateralIfHealthFactorWouldBreak() public depositedCollateral {
        // First mint some DSC
        uint256 amountToMint = 8000 ether; // Close to max allowed
        vm.startPrank(USER);
        dsce.mintDsc(amountToMint);
        
        // Try to redeem most of the collateral while having DSC minted
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL - 0.1 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralForDsc() public depositedCollateral {
        uint256 amountToMint = 100 ether;
        vm.startPrank(USER);
        dsce.mintDsc(amountToMint);
        dsc.approve(address(dsce), amountToMint);
        
        // Redeem half of collateral and burn equivalent DSC
        uint256 amountCollateralToRedeem = AMOUNT_COLLATERAL / 2;
        dsce.redeemCollateralForDSC(weth, amountCollateralToRedeem, amountToMint / 2);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountToMint / 2);
        assertEq(
            collateralValueInUsd,
            dsce.getUsdValue(weth, AMOUNT_COLLATERAL - amountCollateralToRedeem)
        );
    }

    function testMultipleCollateralDeposits() public {
        // Make multiple deposits and verify total collateral
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), (AMOUNT_COLLATERAL / 5) * 3);
        
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL / 5);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL / 5);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL / 5);
        vm.stopPrank();

        (,uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(collateralValueInUsd, dsce.getUsdValue(weth, (AMOUNT_COLLATERAL / 5) * 3));
    }

    function testLiquidation() public depositedCollateral {
        // Setup: USER mints maximum DSC
        uint256 amountToMint = 8000 ether; // Assuming this brings health factor close to minimum
        vm.startPrank(USER);
        dsce.mintDsc(amountToMint);
        vm.stopPrank();

        // Setup: Create a price drop to make USER's position liquidatable
        int256 newPrice = 1500e8; // Drop ETH price to $1500
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newPrice);

        // Setup: LIQUIDATOR gets DSC to liquidate USER
        address LIQUIDATOR = makeAddr("liquidator");
        ERC20Mock(weth).mint(LIQUIDATOR, 2 * AMOUNT_COLLATERAL);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), 2 * AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, 2 * AMOUNT_COLLATERAL, amountToMint);
        (uint256 liquidatorDscMintedBefore, uint256 collateralValueInUsdBefore) = dsce.getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMintedBefore, amountToMint);
        assertEq(collateralValueInUsdBefore, 2 * AMOUNT_COLLATERAL * 1500); // 1500e8 is new price
        dsc.approve(address(dsce), amountToMint);

        // Perform liquidation
        dsce.liquidate(weth, USER, amountToMint);
        vm.stopPrank();

        // Verify USER's position is liquidated
        (uint256 userDscMinted,) = dsce.getAccountInformation(USER);
        (uint256 liquidatorDscMintedAfter, ) = dsce.getAccountInformation(LIQUIDATOR);
        assertEq(userDscMinted, 0);
        assertEq(liquidatorDscMintedAfter, 0); // Should be 0 since DSC was burned
        
        // Calculate expected collateral received (proportional + bonus)
        uint256 expectedCollateral = (amountToMint / 1500); // 1500e8 is new price
        expectedCollateral = expectedCollateral +
            (expectedCollateral * dsce.LIQUIDATION_BONUS()) / dsce.LIQUIDATION_PRECISION();
        uint256 liquidatorCollateralAfter = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        assertEq(
            liquidatorCollateralAfter,
            expectedCollateral,
            "Liquidator should receive proportional collateral plus bonus"
        );
    }

    function testRevertLiquidationIfHealthFactorOk() public depositedCollateral {
        // Try to liquidate a healthy position
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, 100);
        vm.stopPrank();
    }

    function testLiquidationWithMultipleCollateral() public depositedCollateral {
        // Setup: USER mints maximum DSC
        uint256 amountToMint = 8000 ether;
        vm.startPrank(USER);
        dsce.mintDsc(amountToMint);
        vm.stopPrank();

        // Create a severe price drop
        int256 newPrice = 1500e8; // Dramatic price drop to $1500
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newPrice);

        // Setup liquidator with enough DSC
        address liquidator = makeAddr("liquidator");
        ERC20Mock(weth).mint(liquidator, 2 * AMOUNT_COLLATERAL);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), 2 * AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, 2 * AMOUNT_COLLATERAL, amountToMint);
        dsc.approve(address(dsce), amountToMint);

        // Partial liquidation
        uint256 partialLiquidationAmount = amountToMint / 2;
        dsce.liquidate(weth, USER, partialLiquidationAmount);
        vm.stopPrank();

        // Verify partial liquidation results
        (uint256 userDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(userDscMinted, amountToMint - partialLiquidationAmount);
    }

    function testHealthFactorCanReachMaxUint() public depositedCollateral {
        vm.startPrank(USER);
        // No DSC minted, should return type(uint256).max
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, type(uint256).max);
        vm.stopPrank();
    }

    function testLiquidationWithZeroCollateralValue() public {
        // Setup a user with collateral
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 amountToMint = 100 ether;
        dsce.mintDsc(amountToMint);
        vm.stopPrank();

        // Setup liquidator
        address liquidator = makeAddr("liquidator");
        vm.startPrank(liquidator);
        ERC20Mock(weth).mint(liquidator, AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(amountToMint);
        dsc.approve(address(dsce), amountToMint);

        // Crash the price to zero
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(0);

        // Attempt liquidation
        dsce.liquidate(weth, USER, amountToMint);
        vm.stopPrank();

        (uint256 userDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }

    function testRevertIfTransferFromFails() public {
        // Deploy mock token that always fails transfers
        MockFailedTransferFrom mockToken = new MockFailedTransferFrom();
        address[] memory newTokenAddresses = new address[](1);
        address[] memory newPriceFeedAddresses = new address[](1);
        newTokenAddresses[0] = address(mockToken);
        newPriceFeedAddresses[0] = ethUsdPriceFeed;

        DSCEngine newDsce = new DSCEngine(
            newTokenAddresses,
            newPriceFeedAddresses,
            address(dsc)
        );

        vm.startPrank(USER);
        mockToken.mint(USER, AMOUNT_COLLATERAL);
        mockToken.approve(address(newDsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        newDsce.depositCollateral(address(mockToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertIfMintFails() public depositedCollateral {
        // Break the DSC contract's mint function
        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(DecentralizedStableCoin.mint.selector),
            abi.encode(false)
        );

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        dsce.mintDsc(100);
        vm.stopPrank();
    }
}

// Helper contract for testing failed transfers
contract MockFailedTransferFrom is ERC20Mock {
    constructor() ERC20Mock() {}

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }
}