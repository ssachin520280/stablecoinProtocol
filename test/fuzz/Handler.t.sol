// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;
// Handler is going to narrow down the way we call functions. This way we won't be wasting fuzz rounds trivially.

import {Test, console} from 'forge-std/Test.sol';
import {DSCEngine} from '../../src/DSCEngine.sol';
import {DecentralizedStableCoin} from '../../src/DecentralizedStableCoin.sol';
import {ERC20Mock} from '@openzeppelin/contracts/mocks/token/ERC20Mock.sol';
import {MockV3Aggregator} from '../mocks/MockV3Aggregator.sol';

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // double push (but no issues)
        usersWithCollateralDeposited.push(msg.sender);
    }

    // TODO: We can't redeem all the collateral as we also have minted tokens. So, maxCollateralToRedeem needs to be changed.
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);
        vm.startPrank(msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if(amountCollateral == 0) {
            vm.stopPrank();
            return;
        }
        dsce.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 addressSeed, uint256 amount) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        vm.startPrank(sender);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint <= 0) {
            vm.stopPrank();
            return;
        }
        amount = bound(amount, 1, uint256(maxDscToMint));
        timesMintIsCalled++;
        dsce.mintDsc(amount);
        vm.stopPrank();
    }

    // This breaks our invariant test suite!!!!
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper functions

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        return collateralSeed % 2 == 0 ? weth : wbtc;
    }
}